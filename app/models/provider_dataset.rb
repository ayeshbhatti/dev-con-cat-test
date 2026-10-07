class ProviderDataset < ApplicationRecord
  validates :name, presence: true, uniqueness: true
end
