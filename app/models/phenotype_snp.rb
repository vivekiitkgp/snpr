class PhenotypeSnp < ActiveRecord::Base
  include PgSearchCommon

  belongs_to :snp
  belongs_to :phenotype

  def self.update_phenotypes
    max_age = 30.days.ago

    Snp.select([ :id, :ranking ]).
      where([ 'updated_at > ?', max_age]).find_each do |snp|
      Sidekiq::Client.enqueue(LinkSnpPhenotype, snp.id)
    end
  end
end
