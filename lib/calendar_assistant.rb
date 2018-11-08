# coding: utf-8
require "google/apis/calendar_v3"
require "json"
require "yaml"
require "business_time"
require "rainbow"
require "set"

require "calendar_assistant/version"

class CalendarAssistant
  GCal = Google::Apis::CalendarV3

  class BaseException < RuntimeError ; end

  EMOJI_WORLDMAP  = "🗺" # U+1F5FA WORLD MAP
  EMOJI_PLANE     = "🛪" # U+1F6EA NORTHEAST-POINTING AIRPLANE
  EMOJI_1_1       = "👫" # MAN AND WOMAN HOLDING HANDS

  DEFAULT_CALENDAR_ID = "primary"

  attr_reader :service, :calendar, :config

  def self.authorize profile_name
    config = CalendarAssistant::Config.new
    Authorizer.new(profile_name, config.token_store).authorize
  end

  def self.date_range_cast time_range
    time_range.first.to_date..(time_range.last + 1.day).to_date
  end

  def initialize config=CalendarAssistant::Config.new,
                 event_repository_factory: EventRepositoryFactory
    @config = config

    if filename = config.options[:local_store]
      @service = CalendarAssistant::LocalService.new(file: filename)
    else
      @service = Authorizer.new(config.profile_name, config.token_store).service
    end
    @calendar = service.get_calendar DEFAULT_CALENDAR_ID
    @event_repository_factory = event_repository_factory
    @event_repositories = {} # calendar_id → event_repository
  end

  def in_env &block
    # this is totally not thread-safe
    orig_b_o_d = BusinessTime::Config.beginning_of_workday
    orig_e_o_d = BusinessTime::Config.end_of_workday
    begin
      BusinessTime::Config.beginning_of_workday = config.setting(Config::Keys::Settings::START_OF_DAY)
      BusinessTime::Config.end_of_workday = config.setting(Config::Keys::Settings::END_OF_DAY)
      in_tz calendar.time_zone do
        yield
      end
    ensure
      BusinessTime::Config.beginning_of_workday = orig_b_o_d
      BusinessTime::Config.end_of_workday = orig_e_o_d
    end
  end

  def in_tz time_zone, &block
    # this is totally not thread-safe
    orig_time_tz = Time.zone
    orig_env_tz = ENV['TZ']
    begin
      unless time_zone.nil?
        Time.zone = time_zone
        ENV['TZ'] = time_zone
      end
      yield
    ensure
      Time.zone = orig_time_tz
      ENV['TZ'] = orig_env_tz
    end
  end

  def find_events time_range, calendar_id: nil
    calendar_id ||= DEFAULT_CALENDAR_ID
    event_repository(calendar_id).find(time_range)
  end

  def availability time_range
    Scheduler.new(self, config: config).available_blocks(time_range)
  end

  def find_location_events time_range
    event_repository.find(time_range).select { |e| e.location_event? }
  end

  def create_location_event time_range, location
    # find pre-existing events that overlap
    existing_events = find_location_events time_range

    # augment event end date appropriately
    range = CalendarAssistant.date_range_cast time_range

    deleted_events = []
    modified_events = []

    event = event_repository.create(transparency: GCal::Event::Transparency::TRANSPARENT, start: range.first, end: range.last , summary: "#{EMOJI_WORLDMAP}  #{location}")

    existing_events.each do |existing_event|
      if existing_event.start.date >= event.start.date && existing_event.end.date <= event.end.date
        event_repository.delete existing_event
        deleted_events << existing_event
      elsif existing_event.start.date <= event.end.date && existing_event.end.date > event.end.date
        event_repository.update existing_event, start: range.last
        modified_events << existing_event
      elsif existing_event.start.date < event.start.date && existing_event.end.date >= event.start.date
        event_repository.update existing_event, end: range.first
        modified_events << existing_event
      end
    end

    response = {created: [event]}
    response[:deleted] = deleted_events unless deleted_events.empty?
    response[:modified] = modified_events unless modified_events.empty?
    response
  end

  def event_description event
    s = sprintf("%-25.25s", event_date_description(event))

    date_ansi_codes = []
    date_ansi_codes << :bright if event.current?
    date_ansi_codes << :faint if event.past?
    s = date_ansi_codes.inject(Rainbow(s)) { |text, ansi| text.send ansi }

    s += Rainbow(sprintf(" | %s", event.view_summary)).bold

    attributes = []
    unless event.private?
      attributes << "recurring" if event.recurring_event_id
      attributes << "not-busy" unless event.busy?
      attributes << "self" if event.human_attendees.nil? && event.visibility != "private"
      attributes << "1:1" if event.one_on_one?
      attributes << "awaiting" if event.awaiting?
    end

    attributes << event.visibility if event.explicit_visibility?

    s += Rainbow(sprintf(" (%s)", attributes.to_a.sort.join(", "))).italic unless attributes.empty?

    s = Rainbow(Rainbow.uncolor(s)).faint.strike if event.declined?

    s
  end

  def event_date_description event
    if event.all_day?
      start_date = event.start.to_date
      end_date = event.end.to_date
      if (end_date - start_date) <= 1
        event.start.to_s
      else
        sprintf("%s - %s", start_date, end_date - 1.day)
      end
    else
      if event.start.date_time.to_date == event.end.date_time.to_date
        sprintf("%s - %s", event.start.date_time.strftime("%Y-%m-%d  %H:%M"), event.end.date_time.strftime("%H:%M"))
      else
        sprintf("%s  -  %s", event.start.date_time.strftime("%Y-%m-%d %H:%M"), event.end.date_time.strftime("%Y-%m-%d %H:%M"))
      end
    end
  end

  def event_repository calendar_id=DEFAULT_CALENDAR_ID
    @event_repositories[calendar_id] ||= @event_repository_factory.new_event_repository(@service, calendar_id)
  end

  private

  def self.available_block start_time, end_time
    Google::Apis::CalendarV3::Event.new(
      start: Google::Apis::CalendarV3::EventDateTime.new(date_time: start_time),
      end: Google::Apis::CalendarV3::EventDateTime.new(date_time: end_time),
      summary: "available"
    )
  end
end

require "calendar_assistant/config"
require "calendar_assistant/authorizer"
require "calendar_assistant/cli"
require "calendar_assistant/string_helpers"
require "calendar_assistant/date_helpers"
require "calendar_assistant/extensions/event_date_time_extensions"
require "calendar_assistant/extensions/event_extensions"
require "calendar_assistant/event"
require "calendar_assistant/event_repository"
require "calendar_assistant/event_repository_factory"
require "calendar_assistant/scheduler"
require "calendar_assistant/extensions/rainbow_extensions"
require "calendar_assistant/local_service"
