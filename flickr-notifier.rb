=begin

flickr-notifier

Gets recent activity against a user's flickr account and notifies the user via Growl

Dependencies: The awesome flickraw gem and growlnotify
You will need your own API key - see the README at 
    http://github.com/novemberkilo/flickr-notifier/

Author: Navin Keswani
Date: April 2010
License: Per flickraw, growlnotify and the MIT license. See License section of the README at
    http://github.com/novemberkilo/flickr-notifier/

=end

FlickRawOptions = {
    "api_key" => "YOUR FLICKR API KEY HERE",
    "shared_secret" => "YOUR FLICKR SHARED SECRET HERE",
#    "auth_token" => "... Your saved token..."  # if you set this you will be automatically loggued
    "lazyload" => true,     # This delay the loading of the library until the first call

    # Proxy support. alternatively, you can use the http_proxy environment variable
#    "proxy_host" => "proxy_host",
#   "proxy_port" => "proxy_port",
#    "proxy_user" => "proxy_user",
#    "proxy_password" => "proxy_password",

    "timeout" => 5,                # Set the request timeout
#    "auth_token" => "SAVED_TOKEN"  # Set the initial token
  }

require 'rubygems'
require 'flickraw'
require 'logger'

# Set up log file
file = File.open('flickr-notifier-log.log', File::WRONLY | File::APPEND | File::CREAT)

# Start the log over whenever the log exceeds 1 megabyte in size
$LOG = Logger.new(file, 0, 1024 * 1024)

$LOG.level = Logger::DEBUG

AUTH_TOKEN_FILE = ".flickr_auth_token"

def authenticate

  # Follows flickraw's recommended authentication flow.
  # Checks if an AUTH_TOKEN_FILE exists and extracts the 
  # authentication token from it if it does. Else, follows
  # flickraw's recipe for obtaining a frob and then a token 
  # and writes the token to AUTH_TOKEN_FILE 

  if File.exist? AUTH_TOKEN_FILE
    auth_token = File.open(AUTH_TOKEN_FILE).gets
    auth = flickr.auth.checkToken :auth_token => auth_token
    $LOG.add(Logger::DEBUG) {"Successfully read auth_token"}
  else # get an auth_token from Flickr
    frob = flickr.auth.getFrob
    $LOG.add(Logger::DEBUG) {"Obtained frob from flickr"}
    auth_url = FlickRaw.auth_url :frob => frob, :perms => 'read'
    puts "Open this url in your browser to complete the authentication process : #{auth_url}"
    puts "Press Enter when you are finished."
    STDIN.getc
    begin
      auth_token = flickr.auth.getToken :frob => frob
      login = flickr.test.login
      File.new(AUTH_TOKEN_FILE,"w+").write(auth_token.token)
      puts "You are now authenticated as #{login.username} with token #{auth_token.token}"
    rescue FlickRaw::FailedResponse => e
      puts "Authentication failed : #{e.msg}"
      $LOG.add(Logger::ERROR) {"Authentication failed : #{e.msg}"}
    end
  end
end

def download_photo (photo_filename,photo_specs)

  # Returns true if photo downloaded (i.e. a new file created in
  # the ./.images directory, else false.
  # Takes two arguments - photo_filename and photo_specs
  # Expects photo_filename to be a string representation
  # of the path of the file
  # Expects json specification of the photo in photo_specs 
  # URL parsing and file writing per a code snippet from DZone Snippets 

  unless File.exists?(photo_filename)
    begin
      url = URI.parse(FlickRaw.url_s(photo_specs))
      Net::HTTP.start(url.host) do |http|
        resp = http.get(url.path)
        File::open(photo_filename,"w+") do |file|
          file.write(resp.body)
        end
      end
    end
    true
  end
  false
  rescue Exception => msg
    # display system generated message
  puts msg
  $LOG.add(Logger::ERROR){"Downloading of thumbnail of #{photo_filename} failed : #{msg}"}
end

def notify (title='', message='', icon_filename =".images/Flickr-logo.jpg", sticky = false)

  # Tuck the growl notifications here - if we need to change the notification
  # mechanism then this method can be overloaded or modified to suit
  # puts "In notify with icon_filename #{icon_filename}"

   $LOG.add(Logger::DEBUG){"Calling growlnotify with message #{message}"}
  `growlnotify #{(sticky)? '-s':''} --image #{icon_filename} -m "#{message}" "#{title}"`
end

def get_recent_activity (timeframe)

  # Expects timeframe - a string specifying the period 
  # over which to retrieve activity.
  # Compiles a notification of new comments made on the 
  # user's photostream. 
  # Only reports activity once - i.e. a recent comment will not be 
  # replayed every time this method is called. 

  $LOG.add(Logger::DEBUG){"Checking recent activity"}
  unless defined? @displayed_comments
    @displayed_comments=[]  # array to hold ids for comments that have been displayed
  end

  recent_activity = flickr.activity.userPhotos(:timeframe => timeframe)

  if recent_activity.to_a.length == 0 then
    # don't display anything, nothing to do
     $LOG.add(Logger::DEBUG){"Called flickr.activity - nothing new to report"}
    return
  else
    $LOG.add(Logger::DEBUG){"Called flickr.activity - recent activity detected"}
    recent_activity.each do |x|
      message = ''
      photo_id = x.id
      x.activity.event.each do |z|
        case
        when z.type == "comment" then
          begin
            unless @displayed_comments.include? z.commentid
              @displayed_comments.push z.commentid 
              message << "Comment: " << z._content << "\n"
            end
          end
        when z.type == "fave" then
          begin
            unless @displayed_comments.include? [photo_id, z.user]
              @displayed_comments.push [photo_id, z.user]
              message << "Added as a favorite\n"
            end
          end
        end
        unless (message == '')   # Which can happen if recent_activity is neither a comment nor a fave
          message << "User: " << z.username << "\n"
          time_added = Time.at(z.dateadded.to_i)
          message << time_added.to_s << "\n"
        end
      end
      unless (message == '')
        title = x.title                              # Get the photo's title
        photo_id = x.id                              
        photo_filename = ".images/#{photo_id}.jpg"   # Filename of the thumbnail
        download_photo(photo_filename,x)
        notify(title, message, photo_filename,true)
      end
    end
  end
end

def get_stats(date)

  # Expects date - a string of format "YYYY-MM-DD"
  # Calls flickr.stats.getTotalViews(date) to pick up 
  # summary of activity and flickr.stats.getPopularPhotos(date)
  # to get 5 most popular photos

  $LOG.add(Logger::DEBUG){"Checking stats for date #{date}"}
  title = "Flickr stream views for today"
  all_quiet_message = "All quiet at your photostream"
  todays_stats = flickr.stats.getTotalViews(:date => date)
  if todays_stats.photos.views.to_s == "0" then
    $LOG.add(Logger::DEBUG){"Called flickr.stats - no stats to report"}
    notify(title, all_quiet_message, ".images/Flickr-logo.jpg",true)
  else
    message = ''
    todays_stats.to_hash.each do |key,x| 
      message << "#{key.capitalize}: #{x.views}" << "\n" 
    end
    $LOG.add(Logger::DEBUG){"Compiled summary of today's stats #{message}"}
    notify(title,message,".images/Flickr-logo.jpg",true)

    title = "Today's top 5 popular photos"
    message = ''
    # Get stats on at most 5 popular photos

    recent_view_stats = flickr.stats.getPopularPhotos(:date => date, :per_page => '5', :page => '1')
    $LOG.add(Logger::DEBUG){"Called flickr.stats - compiling notification message"}
    
    recent_view_stats.each do |x|
      message << x.title << "\n"
      if (x.stats.comments > 0)
        message << "\t: " << "commented on " << x.stats.comments.to_s << " times\n"
      end
      if (x.stats.favorites > 0)
        message << "\t: " << "marked as a favourite " << x.stats.favorites.to_s << " times\n"
      end
      message << "\t: " << "viewed " << x.stats.views.to_s << " times\n"
    end
    # puts message
    notify(title, message,".images/Flickr-logo.jpg",true)
    # `growlnotify -s -m "#{message}" "#{title}"`
  end
end

begin
  timeframe = '1d'  # Pick up today's (GMT) activity
  sleep_period = 15 # Recommend not making this smaller than 15
  # Flickr requests that the recent_activity method not be called more
  # than once an hour so any more than 4 times in an hour will be very cheeky!
  # Report on view counts once every hour (within the first quarter of the hour)
  
  # Set up the .image directory unless it already exists
  Dir.mkdir(".images") if Dir.glob(".images")==[]
  
  $LOG.add(Logger::DEBUG){ "About to call authenticate" }
  authenticate
  $LOG.add(Logger::DEBUG){"Authentication complete"}
  while true do
    get_recent_activity(timeframe)
    $LOG.add(Logger::DEBUG){"Returned from call to get_recent_activity"}
    t = Time.now
    if t.min < 15   # we are in the first quarter of a new hour
      # convert to GMT and format as a "YYYY-MM-DD" string
      get_stats(t.getgm.strftime("%Y-%m-%d"))
      $LOG.add(Logger::DEBUG){"Returned from call to get_stats"}
    end
    $LOG.add(Logger::DEBUG){"About to go to sleep"}
    sleep (60*sleep_period)
    $LOG.add(Logger::DEBUG){"Just woke up"}
  end
  rescue
    $LOG.add(Logger::ERROR){"Fatal error - in rescue block"}
    puts "Oops, something went wrong with flickr-notifier."
    puts "Is Growl running? (Check system preferences)"
    puts "Did you put your flickr API key and secret into flickr-notifier.rb?"
    puts "Did your internet connection drop out?"
end


