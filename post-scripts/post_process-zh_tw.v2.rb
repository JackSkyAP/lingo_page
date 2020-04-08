#!/usr/bin/ruby
# encoding: UTF-8

require "trollop"
require File.expand_path('../../../lib/recordandplayback', __FILE__)

opts = Trollop::options do
  opt :meeting_id, "Meeting id to archive", :type => String
  opt :format, "Playback format name", :type => String
end
meeting_id = opts[:meeting_id]

logger = Logger.new("/var/log/bigbluebutton/post_process.log", 'weekly' )
logger.level = Logger::INFO
BigBlueButton.logger = logger

processed_files = "/var/bigbluebutton/recording/process/presentation/#{meeting_id}"
meeting_metadata = BigBlueButton::Events.get_meeting_metadata("/var/bigbluebutton/recording/raw/#{meeting_id}/events.xml")

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
    bodyString = "[#{serverName}] - 同步教室 "
    serverName = "https://#{serverName}"
    meetingName = "#{courseName} - #{meetingName}"
    mId = meetingId.split("-")
    courseId= mId[1] 
    courseLink = "課程: <a href='#{serverName}/course/view.php?id=#{courseId}' >#{meetingName}</a>"
    bodyString = "#{bodyString} - #{courseLink}"
end

#bodyString = "The meeting #{hostString} is archive.<br/> #{meeting_metadata}, \r Processed file in #{processed_files}"
#bodyString = "同步教室 #{hostString} - 課程: #{meetingName} 開始進行轉檔.\r\n處理過的檔案將會在 #{processed_files} 目錄內."
#bodyString = bodyString + "Processed file in #{processed_files}"
bodyString = "#{bodyString} 開始進行轉檔處理, 請稍候.<br/>處理過的檔案將會在 #{processed_files} 目錄內."
#subjectString = "#{meetingName} archive"
subjectString = "同步教室 #{meetingName} 開始進行轉檔"

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
