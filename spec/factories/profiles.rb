FactoryGirl.define do
  factory :profile do
    access_token { nil }
    fb_id { Random.rand(1000000000 .. 10000000000).to_s }
    name { Faker::Name.name }
    birthday { Random.rand(3000 .. 30000).days.ago }
    gender { ['male', 'female'].sample }
    relationship_status { ['Single', 'In a Relationship', 'In an Open Relationship', 'Engaged', 'Married', 'It\'s Complicated', 'Widowed'].sample }
    picture_url { "http://www.gravatar.com/avatar/#{Digest::MD5.hexdigest(Faker::Internet.email)}" }
  end
end
