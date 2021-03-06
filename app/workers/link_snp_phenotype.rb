class LinkSnpPhenotype
  include Sidekiq::Worker
  sidekiq_options :queue => :link_snp_phenotype, :unique => true
  attr_reader :snp, :characteristics, :papers_count

  def perform(snp_id)
    @snp = Snp.find(snp_id)
    @characteristics = Phenotype.all.map { |x| x.characteristic }
    @papers_count = @snp.snp_references.count

    @snp.update_column(:phenotype_updated, Time.current)
    score_phenotype snp
  end

  # Compute score corresponding to all references for a SNP and return top 10
  # phenotypes sorted by score.
  def score_phenotype(snp)
    snpedia = score_paper(:snpedia_papers, 5.0)
    plos = score_paper(:plos_papers, 2.0)
    pgp = score_paper(:pgp_annotations, 2.0)
    genomegov = score_paper(:genome_gov_papers, 2.0)
    mendeley = score_paper(:mendeley_papers, 1.0)

    # merge scores from same phenotype across all reference collections
    all_scores = [snpedia, pgp, genomegov, mendeley].reduce(plos) do |x, y|
      x.merge(y) do |k, v1, v2|
        v1 + v2
      end
    end

    # normalize to total number of references
    all_scores.each {|k, v| all_scores[k] /= @papers_count}

    all_scores = all_scores.sort_by {|k, v| v}

    all_scores.take(10).each do |k, v|
      ph = Phenotype.find_by_characteristic(k)
      PhenotypeSnp.find_or_create_by(snp_id: snp.id,
                                     phenotype_id: ph.id)
                  .update_attributes!(score:  v)
    end
  end

  # Score each reference based on the number of phenotype keywords found in the
  # metadata. The weight for each count is received from the calling function.
  def score_paper(paper_type, weight)
    score = {}

    papers = @snp.public_send(paper_type)

    # search for each phenotype one by one in the papers' metadata
    @characteristics.each do |chr|
      papers.each do |p|
        title = p.respond_to?(:title) ? p.title : p.summary

        if title.downcase.include? chr
          score[chr] = 0.0 if score[chr].nil?
          score[chr] += weight
        end
      end

      unless score[chr].nil?
        score[chr] /= papers.length
      end
    end
    score
  end
end
