# coding: utf-8
require "google_calendar"
require "json"
require "yaml"
require "business_time"

class CalendarAssistant
  attr_reader :calendar

  CLIENT_ID_FILE = "client_id.json"
  CALENDAR_TOKENS_FILE = "calendar_tokens.yml"
  
  EMOJI_WORLDMAP  = "🗺" # U+1F5FA WORLD MAP
  EMOJI_PUSHPIN   = "📍" # U+1F4CD ROUND PUSHPIN
  EMOJI_FLAG      = "🚩" # U+1F6A9 TRIANGULAR FLAG ON POST
  EMOJI_PLANE     = "🛪" # U+1F6EA NORTHEAST-POINTING AIRPLANE
  EMOJI_1_1       = "👫" # MAN AND WOMAN HOLDING HANDS

  def self.token_for calendar_id
    calendar_tokens = File.exists?(CALENDAR_TOKENS_FILE) ?
                        YAML.load(File.read(CALENDAR_TOKENS_FILE)) :
                        Hash.new
    calendar_tokens[calendar_id]
  end

  def self.save_token_for calendar_id, refresh_token
    calendar_tokens = File.exists?(CALENDAR_TOKENS_FILE) ?
                        YAML.load(File.read(CALENDAR_TOKENS_FILE)) :
                        Hash.new
    calendar_tokens[calendar_id] = refresh_token
    File.open(CALENDAR_TOKENS_FILE, "w") { |f| f.write calendar_tokens.to_yaml }
  end

  def self.params_for calendar_id
    client_id = JSON.parse(File.read(CLIENT_ID_FILE))
    {
      :client_id     => client_id["installed"]["client_id"],
      :client_secret => client_id["installed"]["client_secret"],
      :calendar      => calendar_id,
      :redirect_url  => "urn:ietf:wg:oauth:2.0:oob",
      :refresh_token => CalendarAssistant.token_for(calendar_id),
    }
  end

  def self.calendar_for calendar_id
    Google::Calendar.new params_for(calendar_id)
  end

  def self.calendar_list_for calendar_id
    Google::CalendarList.new params_for(calendar_id)
  end

  def self.time_or_time_range userspec
    if userspec =~ /\.\.\./
      start_userspec, end_userspec = userspec.split("...")
      start_time = Chronic.parse start_userspec.strip
      end_time   = Chronic.parse end_userspec.strip
      return start_time..end_time
    end
    Chronic.parse userspec
  end

  def initialize calendar_id
    @calendar = CalendarAssistant.calendar_for calendar_id
  end

  def create_geographic_event time_or_range, location_name
    start_time = time_or_range
    end_time = nil

    if time_or_range.is_a?(Range)
      start_time = time_or_range.first
      end_time = (time_or_range.last + 1.day).beginning_of_day
    end

    new_event = calendar.create_event do |event|
      event.title = "#{EMOJI_WORLDMAP}  #{location_name}"
      event.all_day = start_time
      event.end_time = end_time if end_time
    end

    pp new_event.raw if new_event.respond_to?(:raw)

    return new_event
  end

  def find_geographic_events time_or_range
    events = if time_or_range.is_a?(Range)
               calendar.find_events_in_range time_or_range.first, time_or_range.last, max_results: 2000
             else
               end_time = (time_or_range + 1.day).beginning_of_day
               calendar.find_events_in_range time_or_range, end_time, max_results: 2000
             end
    events.find_all(&:assistant_geographic_event?)
  end
end

require "calendar_assistant/cli"
require "calendar_assistant/event_extensions"
