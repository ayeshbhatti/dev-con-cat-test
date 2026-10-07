abort "This script is only for local development." unless Rails.env.development?

dataset = ProviderDataset.find_by!(name: "trustedform")
data = dataset.data.deep_dup

data.fetch("results").fetch("L-1001").merge!(
  "page_url" => "http://localhost:3000/demo.html",
  "fixture_context" => "Synthetic consent evidence for the local demo page"
)

dataset.update!(data: data)
puts "Maria's local TrustedForm fixture now matches the demo page."
