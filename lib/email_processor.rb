class EmailProcessor

  def initialize(email)
    @email = email
    @tracker = Staccato.tracker(AppSettings['settings.google_analytics_id']) if google_analytics_enabled?
  end

  def process

    # Guard clause to prevent ESPs like Sendgrid from posting over and over again
    # if the email presented is invalid and generates a 500.  Returns a 200
    # error as discussed on https://sendgrid.com/docs/API_Reference/Webhooks/parse.html
    # This error happened with invalid email addresses from PureChat
    return if @email[:from].addrs.first.address.match(/\A[^@\s]+@([^@\s]+\.)+[^@\s]+\z/).blank?

    # scan users DB for sender email
    @user = User.where("lower(email) = ?", @email[:from].addrs.first.address.downcase).first
    if @user.nil?
      create_user
    end

    sitename = AppSettings["settings.site_name"]
    message = get_content_from_mail
    raw = @email.body.raw_source.nil? ? "" : @email.body.raw_source

    subject = @email.subject
    attachments = @email.attachments

    if subject.include?("[#{sitename}]") # this is a reply to an existing topic

      complete_subject = subject.split("[#{sitename}]")[1].strip
      ticket_number = complete_subject.split("-")[0].split("#")[1].strip
      topic = Topic.find(ticket_number)

      #insert post to new topic
      message = "Attachments:" if @email.attachments.present? && @email.body.blank?
      post = topic.posts.create(
        :body => message.encode('utf-8', invalid: :replace, replace: '?'),
        :raw_email => raw.encode('utf-8', invalid: :replace, replace: '?'),
        :user_id => @user.id,
        :kind => "reply"
      )

      # Push array of attachments and send to Cloudinary
      handle_attachments(@email, post)

      if @tracker
        @tracker.event(category: "Email", action: "Inbound", label: "Reply", non_interactive: true)
        @tracker.event(category: "Agent: #{topic.assigned_user.name}", action: "User Replied by Email", label: topic.to_param) unless topic.assigned_user.nil?
      end
    elsif subject.include?("Fwd: ") # this is a forwarded message DOES NOT WORK CURRENTLY

      #clean message
      # message = MailExtract.new(message).body

      #parse_forwarded_message(message)
      topic = Forum.first.topics.create!(
        :name => subject,
        :user_id => @user.id,
        :private => true
      )

      #insert post to new topic
      message = "Attachments:" if @email.attachments.present? && @email.body.blank?
      post = topic.posts.create!(
        :body => message.encode('utf-8', invalid: :replace, replace: '?'),
        :raw_email => raw.encode('utf-8', invalid: :replace, replace: '?'),
        :user_id => @user.id,
        kind: 'first'
      )

      # Push array of attachments and send to Cloudinary
      handle_attachments(@email, post)

      # Call to GA
      if @tracker
        @tracker.event(category: "Email", action: "Inbound", label: "Forwarded New Topic", non_interactive: true)
        @tracker.event(category: "Agent: Unassigned", action: "Forwarded New", label: topic.to_param)
      end
    else # this is a new direct message

      topic = Forum.first.topics.create(:name => subject, :user_id => @user.id, :private => true)
      # if @email.header['X-Helpy-Teams'].present?
      #   topic.team_list = @email.header['X-Helpy-Teams']

      #if @email.to[0][:token].include?("+")
      #  topic.team_list.add(@email.to[0][:token].split('+')[1])
      #  topic.save
      #elsif @email.to[0][:token] != 'support'
      #  topic.team_list.add(@email.to[0][:token])
      #  topic.save
      #end

      #insert post to new topic
      message = "Attachments:" if @email.attachments.present? && @email.body.blank?
      post = topic.posts.create(
        :body => message.encode('utf-8', invalid: :replace, replace: '?'),
        :raw_email => raw.encode('utf-8', invalid: :replace, replace: '?'),
        :user_id => @user.id,
        :kind => "first"
      )

      # Push array of attachments and send to Cloudinary
      handle_attachments(@email, post)

      # Call to GA
      if @tracker
        @tracker.event(category: "Email", action: "Inbound", label: "New Topic", non_interactive: true)
        @tracker.event(category: "Agent: Unassigned", action: "New", label: topic.to_param)
      end
    end

  # rescue
  #   render status: 200
  end

  def handle_attachments(email, post)
    if email.attachments.present? && cloudinary_enabled?
      array_of_files = []
      email.attachments.each do |attachment|
        array_of_files << File.open(attachment.tempfile.path, 'r')
      end
      post.screenshots = array_of_files
    elsif email.attachments.present?
      post.update(
        attachments: email.attachments
      )
      if post.valid?
        post.save
      end
    end
  end

  def cloudinary_enabled?
    AppSettings['cloudinary.cloud_name'].present? && AppSettings['cloudinary.api_key'].present? && AppSettings['cloudinary.api_secret'].present?
  end

  def google_analytics_enabled?
    AppSettings['settings.google_analytics_enabled'] == '1'
  end

  def create_user
    # create user
    @user = User.new

    @token, enc = Devise.token_generator.generate(User, :reset_password_token)
    @user.reset_password_token = enc
    @user.reset_password_sent_at = Time.now.utc

    @user.email = get_email_from_mail
    @user.name = get_name_from_mail.blank? ? get_token_from_mail : get_name_from_mail
    @user.password = User.create_password
    if @user.save
      UserMailer.new_user(@user.id, @token).deliver_later
    end

  end

  def get_name_from_mail
    mail_is_mail ? @email[:from].addrs.first.display_name : @email.from[:name]
  end

  def get_email_from_mail
    mail_is_mail ? @email[:from].addrs.first.address : @email.from[:email]
  end

  def get_token_from_mail
    #this seems to only be there for griddler and co
    @email.from[:token]
  end

  def get_content_from_mail
    if mail_is_mail
      @email.multipart? ? (@email.text_part ? @email.text_part.body.decoded : nil) : @email.body.decoded
    else
      MailExtract.new(@email.body).body
    end
  end

  def mail_is_mail
    @email.class.name == 'Mail::Message'
  end
end
