require 'mail'

meeting_id = 'Lingo English 101'

Mail.defaults do
  delivery_method :smtp, {
    :address              => "smtp.gmail.com",
    :port                 => 587,
    :domain               => 'gmail.com',
    :user_name            => 'LINGOSMTP',
    :password             => 'P@SSW0RD',
    :authentication       => 'plain',
    :enable_starttls_auto => true  }
  end

Mail.deliver do
  to 'john@click-ap.com, jack@click-ap.com'
  from 'Lingo <LINGOSMTP@gmail.com>'
  subject "#{meeting_id} publish"
  body 'testing sendmail'
end