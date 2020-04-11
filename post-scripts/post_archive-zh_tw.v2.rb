#!/usr/bin/ruby
# encoding: UTF-8

require "trollop"
require File.expand_path('../../../lib/recordandplayback', __FILE__)

opts = Trollop::options do
  opt :meeting_id, "Meeting id to archive", :type => String
  opt :format, "Playback format name", :type => String
end
meeting_id = opts[:meeting_id]

logger = Logger.new("/var/log/bigbluebutton/post_archive.log", 'weekly' )
logger.level = Logger::INFO
BigBlueButton.logger = logger

archived_files = "/var/bigbluebutton/recording/raw/#{meeting_id}"
meeting_metadata = BigBlueButton::Events.get_meeting_metadata("#{archived_files}/events.xml")

#
# Put your code here
#
require 'mail'

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

meetingId = meeting_metadata.key?("meetingId") ? meeting_metadata["meetingId"].value : nil
serverName = meeting_metadata.key?("bbb-origin-server-name") ? meeting_metadata["bbb-origin-server-name"].value : nil
courseName = meeting_metadata.key?("bbb-context") ? meeting_metadata["bbb-context"].value : nil
meetingName = meeting_metadata.key?("meetingName") ? meeting_metadata["meetingName"].value : nil
meetingName ||= meeting_metadata.key?("title") ? meeting_metadata["title"].value : meeting_id

# for moodle
bodyString = "The meeting #{meetingName}"
unless serverName.nil? && courseName.nil?
    bodyString = "[#{serverName}] - �P�B�Ы� "
    serverName = "https://#{serverName}"
    meetingName = "#{courseName} - #{meetingName}"
    mId = meetingId.split("-")
    courseId= mId[1] 
    courseLink = "�ҵ{: <a href='#{serverName}/course/view.php?id=#{courseId}' >#{meetingName}</a>"
    bodyString = "#{bodyString} - #{courseLink}"
end

#bodyString = "The meeting #{bodyString} is archive.<br/>#{meeting_metadata}, \r Archive file in #{archived_files}"
#bodyString = "#{bodyString} - �P�B�Ыǽҵ{: #{meetingName} �Ҧ��H���w���}�ثeĳ�{, �}�l�i��ʦs.\r\n�ʦs�ɮױN�|�b #{archived_files} �ؿ���."
#bodyString = "#{bodyString} <br/>Archive file in #{archived_files}"
bodyString = "#{bodyString} �Ҧ��H���w���}�ثeĳ�{, �}�l�i��ʦs.<br/>�ʦs�ɮױN�|�b #{archived_files} �ؿ���."
#subjectString = "#{meetingName} archive"
subjectString = "�P�B�Ы� #{meetingName} ĳ�{����-�}�l�i��ʦs"

Mail.deliver do
  to 'rd@click-ap.com'
  from 'Lingo <LINGOSMTP@gmail.com>'
  subject "[Lingo]#{subjectString} "
  
  text_part do
    body "#{bodyString}"
  end
  
  html_part do
    content_type 'text/html; charset=UTF-8'
    body "#{bodyString}"
  end
end

exit 0