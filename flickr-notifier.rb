=begin

flickr-notifier(beta)

Gets recent activity against a user's flickr account and notifies the user via Growl.

Dependencies: The awesome flickraw gem and growlnotify

Author: Navin Keswani
Date: April 2010
License: [TBC] Per flickraw, growlnotify and the MIT license

=end

require 'rubygems'
require 'flickraw'

FlickRaw.api_key = "38d132c8b4966e86987654dad17b656e"
FlickRaw.shared_secret = "627dd83a8161fd83"

AUTH_TOKEN_FILE = ".flickr_auth_token"

def authenticate
  if File.exist? AUTH_TOKEN_FILE
    auth_token = File.open(AUTH_TOKEN_FILE).gets
    auth = flickr.auth.checkToken :auth_token => auth_token
  else # get an auth_token from Flickr
    frob = flickr.auth.getFrob
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
    end
  end
end

def download_photo (photo_filename,photo_specs)

  # Returns true if new file created else false
  # Expects photo_filename to be a string representation
  # of the path of the file.
  # Expects json specification of the photo in photo_specs.
  # Reuses a code snippet from DZone Snippets
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
end

def notify (title='', message='', icon_filename =".images/Flickr-logo.jpg", sticky = false)
  # Tuck the growl notifications here - if we need to change the notification
  # mechanism then this method can be overloaded or modified to suit
  # puts "In notify with icon_filename #{icon_filename}"
  `growlnotify #{(sticky)? '-s':''} --image #{icon_filename} -m "#{message}" "#{title}"`
end

def get_recent_activity (timeframe)
  # Expects timeframe - a string specifying the period over which to retrieve activity

  unless defined? @displayed_comments
    @displayed_comments=[]  # ids for comments that have been displayed
  end
  recent_activity = flickr.activity.userPhotos(:timeframe => timeframe)

  if recent_activity.to_a.length == 0 then
    # don't display anything, nothing to do
    return
  else
    recent_activity.each do |x|
      message = ''
      title = x.title
      photo_id = x.id
      photo_filename = ".images/#{photo_id}.jpg"
      download_photo(photo_filename,x)
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
          message << "Added as a favorite\n"
        end
        unless (message == '')
          message << "User: " << z.username << "\n"
          time_added = Time.at(z.dateadded.to_i)
          message << time_added.to_s << "\n"
        end
      end
      unless (message == '')
        notify(title, message, photo_filename,true)
      end
    end
  end
end

def get_stats(date)
  recent_view_stats = flickr.stats.getPopularPhotos(:date => date)
  title = "Flickr stats for today"
  if recent_view_stats.to_a.length == 0 then
    notify(all_quiet_message)
  else
    message = ''
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
    notify(title, (message=='')? "All quiet at your photostream" : message,".images/Flickr-logo.jpg",true)
    # `growlnotify -s -m "#{message}" "#{title}"`
  end
end

begin
  timeframe = '1d'  # Pick up today's (GMT) activity
  sleep_period = 15 # Recommend not making this smaller than 15
  # Flickr requests that the recent_activity method not be called more
  # than once an hour so any more than 4 times in an hour will be very cheeky!
  # Report on view counts once every hour (within the first quarter)
  authenticate
  while true do
    get_recent_activity(timeframe)
    t = Time.now
    if t.min < 15   # we are in the first quarter of a new hour
      # convert to GMT and format as a "YYYY-MM-DD" string
      get_stats(t.getgm.strftime("%Y-%m-%d"))
    end
    sleep (60*sleep_period)
  end
  rescue
    puts "Oops, something went wrong with flickr-notifier."
    puts "Is Growl running? (Check system preferences)"
    puts "Did your internet connection drop out?"
end


