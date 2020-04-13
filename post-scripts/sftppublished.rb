require 'net/ssh'
require 'net/sftp'

host = '140.128.66.46'
user = 'lingo'

meeting_id = '760cca8bf322cdd7ecdce414f09962dfe60aa424-1586392892643'
remotePath = "/var/bigbluebutton/published/presentation/#{meeting_id}"
doneFile = "/var/bigbluebutton/recording/status/published/#{meeting_id}-presentation.done"

Net::SSH.start(host, user) do |ssh|
  ssh.sftp.mkdir! remotePath
  ssh.sftp.upload!(remotePath, remotePath)
  puts ssh.exec!("sudo chown -R bigbluebutton:bigbluebutton #{remotePath}")
  require 'stringio'
  io = StringIO.new("Published #{meeting_id}")
  ssh.sftp.upload!(io, doneFile)
  puts ssh.exec!("sudo chown -R bigbluebutton:bigbluebutton #{doneFile}")
end
