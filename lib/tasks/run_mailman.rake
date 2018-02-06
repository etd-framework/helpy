namespace :helpy do
  desc "Run mailman"
  task :mailman => :environment do

    require 'mailman'
    Mailman.config.poll_interval = 0
    Mailman.config.ignore_stdin = 1

    if AppSettings["email.mail_service"] == 'imap'
      puts 'imap config found'
      imap_port = AppSettings['email.imap_port']
      if imap_port.empty?
        imap_port = AppSettings['email.imap_security'] == 'ssl' ? 993 : 143
      end
      Mailman.config.imap = {
        server: AppSettings['email.imap_server'],
        ssl: AppSettings['email.imap_security'] == 'ssl' ? true : false,
        starttls: AppSettings['email.imap_security'] == 'starttls' ? true : false,
        username: AppSettings['email.imap_username'],
        password: AppSettings['email.imap_password'],
        port: imap_port
      }
    end

    Mailman::Application.run do
      # to AppSettings["email.admin_email"] do
      default do
        begin
          EmailProcessor.new(message).process
        rescue Exception => e
          puts "Error during processing: #{$!}"
          puts "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
        end
      end
    end
  end
end
