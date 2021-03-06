class Profile < ActiveRecord::Base
  # -----------------------------------------------------------------
  # Relations
  # -----------------------------------------------------------------
  belongs_to :access_token
  has_many :relations_of_from_user, class_name: Relation,  primary_key: :fb_id, foreign_key: :fb_id_from, dependent: :destroy
  has_many :relations_of_to_user, class_name: Relation,   primary_key: :fb_id, foreign_key: :fb_id_to, dependent: :destroy
  has_many :friends_of_from_user, through: :relations_of_from_user, source: :to_user
  has_many :friends_of_to_user, through: :relations_of_to_user, source: :from_user
 

  # -----------------------------------------------------------------
  # Scopes
  # -----------------------------------------------------------------
  scope :has_token, -> { where.not(access_token_id: nil) }

  # -----------------------------------------------------------------
  # Public Class Methods
  # -----------------------------------------------------------------
  # Facebook APIの返り値からユーザ情報を作成する
  # すでにいる場合はそれを返す
  # @param [Hash] /me の返り値
  # @param [AccessToken]
  # @return [Profile] ユーザ情報
  def self.insert_or_update(me, token)
    # すでに存在していないか探す
    profile = Profile.where(fb_id: me['id']).first

    if profile.nil?
        if me['gender'].nil?
          me['gender']='empty'
        end
        if me['relationship_status'].nil?
          me['gender']='empty'
        end
      # 存在していない場合新しく作る
      profile = Profile.create!(
        access_token_id: token.id,
        fb_id: me['id'],
        name: me['name'],
        birthday: nil, # TODO
        gender: me['gender'],
        relationship_status: me['relationship_status'],
        picture_url: me['picture'].try { |p| p['data'].try { |d| d['url'] } }
      )
    else
      # 存在している場合、取得したアクセストークンで更新する
      profile.access_token_id = token.id
      profile.save!
    end

    profile
  end


  # -----------------------------------------------------------------
  # Public Class Methods
  # -----------------------------------------------------------------
  # Facebook APIの返り値からprofile情報をDBに格納する
  # @param [Hash] /me/friends の返り値
  # @return 
  def self.insert(friends)
    friends_id = friends.map{ |f| f['id'] }
    #DBに存在している友人を抽出
    already_exist_friends = Profile.where(fb_id: friends_id).pluck(:fb_id)
    friends.each do |friend|
      #TODO 途中で失敗してしまった場合の処理
      #存在していない場合は格納
      if !already_exist_friends.include? friend['id']
        if friend['gender'].nil?
          friend['gender']='empty'
        end
        if friend['relationship_status'].nil?
          friend['relationship_status']='empty'
        end
        data=Profile.create!(
          fb_id:friend['id'],
          name:friend['name'],
          birthday:friend['birthday'],
          age:Profile.age(friend['birthday']),
          gender:friend['gender'],
          relationship_status:friend['relationship_status'],
          picture_url:friend['picture'].try { |p| p['data'].try { |d| d['url'] } },
          )
      end
    end  
  end

  #scope :by_gender, lambda {|gender| where(arel_table[:gender].eq(gender))}
  scope :by_gender, lambda {|gender| where(gender: gender)}
  scope :by_relationship_status, lambda{|relationship_status| where(relationship_status: relationship_status)}
  scope :by_age, lambda {|age_min,age_max| where(arel_table[:age].gteq(age_min).and(arel_table[:age].lteq(age_max)))}
  scope :by_age_null, ->{where(age: nil)}
  # -----------------------------------------------------------------
  # Public Class Methods
  # -----------------------------------------------------------------
  # formデータから検索
  # @param formの値
  # return [Hash] formの値
  def self.search(params={})

    return nil if params[:fb_id].nil?

    profiles = Profile.where(fb_id: params[:fb_id]).first
    profile_result = profiles.friends_of_from_user
                     
    if params[:gender]
        profile_result = profile_result.by_gender(params[:gender])
    end

    if params[:relationship_status]
        profile_result = profile_result.by_relationship_status(params[:relationship_status])
    end
    if params[:no_age].nil?
      if params[:age_min]
      profile_result = profile_result.by_age(params[:age_min],params[:age_max])
      end
    else

      profile_result = profile_result.by_age_null
    end

    return profile_result

  end



  # -----------------------------------------------------------------
  # Public Class Methods
  # -----------------------------------------------------------------
  # ユーザの Friendsのトークンがあるかどうかを確認する
  # Friendsのトークン情報を返す
  # @param [Hash] /me/friendの返り値
  # @return [[Profile]] トークンのある友人の Profile の配列
  def self.checkFriendsToken(me_friends)
    self.has_token.where(fb_id: me_friends.map{ |f| f['id'] })
  end

  # -----------------------------------------------------------------
  # Public Class Methods
  # -----------------------------------------------------------------
  # ユーザーの情報を取得する
  # 
  # @param fb_id
  # 
  def self.getUser(me_fb_id)

      profile = Profile.where(fb_id:me_fb_id).first
      return profile
  
  end

  # fb_id を指定してユーザ情報を取得する。取得できなかった場合 nil を返す
  # @param [String] fb_id
  # @return [Profile]
  def self.find_by_fb_id(fb_id)
    Profile.where(fb_id: fb_id).first
  end

  # 年齢を取得する
  # param [String] birthday
  # @return [Integer] 年齢
  def self.age(birthday)
    formats = ['%m/%d/%Y','%m/%d']
    birth_f = nil
    if birthday
      formats.each do |format|
        begin
          birth_f =Date.strptime(birthday,format)
          break
        rescue ArgumentError
        end
      end
      if birth_f.year == Date.today.year
        #日付しか入っていない場合、年が自動的に今年になってしまうので、年齢はnilを返す
        return nil
      else
        birth = birth_f.strftime('%Y%m%d').to_i
        #birth = Date.parse(birthday).strftime('%Y%m%d').to_i
        today = Date.today.strftime('%Y%m%d').to_i
        return (today - birth) / 10000
      end
      return nil
    end
    return nil
  end

  # 登録の方向関係なく友人を取得する
  def self.all_friends(fb_id)
    user =Profile.where(fb_id:fb_id).first
    return nil if user.nil?
    from_friends =user.friends_of_from_user
    to_friends =user.friends_of_to_user
     return Profile.where(fb_id:from_friends.pluck(:fb_id) | to_friends.pluck(:fb_id))
  end

  # -----------------------------------------------------------------
  # Public Instance Methods
  # -----------------------------------------------------------------
  # Facebook Graph API をインスタンス化する
  # @return [Koala::Facebook::API]
  def api
    self.access_token.try { |t| t.access_token.try { |u| Koala::Facebook::API.new(u) } }
  end

  # FacebookChat::Client のインスタンスを返す
  # @return [FacebookChat::Client]
  def chat_api
    self.access_token.try { |t| t.access_token.try { |u| FacebookChat::Client.new(u) } }
  end


  # 名前と Facebook へのリンクを返す
  # @return [String]
  def name_with_link
    "<a href=\"#{self.facebook_url}\" target=\"_blank\">#{self.name}</a>".html_safe
  end

  # Facebook のページ URL を返す
  # @return [String]
  def facebook_url
    "https://www.facebook.com/#{self.fb_id}"
  end

  # 性別を文字列で返す
  # @return [String] 男性 / 女性 / データなし
  def gender_str
    case self.gender
      when 'male'
        '男性'
      when 'female'
        '女性'
      else
        'データなし'
    end
  end

  # 年齢を文字列で返す
  # @return [String]
  def age_str
    self.age.present? ? "#{self.age}歳" : 'データなし'
  end

  # 交際ステータスを文字列で返す
  # @return [String]
  def relationship_status_str
    {
      'Single' => '独身',
      'In A Relationship' => '交際中',
      'Engaged' => '婚約中',
      'Married' => '既婚',
      'It\'s Complicated' => '複雑な関係',
      'In An Open Relationship' => 'オープンな関係',
      'Widowed' => '配偶者と死別',
      'Separated' => '別居',
      'Divorced' => '離婚',
    }[self.relationship_status].presence || 'データなし'
  end


end
