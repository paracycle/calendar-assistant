# coding: utf-8
require "google/apis/calendar_v3"
require "json"
require "yaml"
require "business_time"
require "ice_cube"
require "rainbow"
require "set"

class CalendarAssistant
  GCal = Google::Apis::CalendarV3

  EMOJI_WORLDMAP  = "🗺" # U+1F5FA WORLD MAP
  EMOJI_PLANE     = "🛪" # U+1F6EA NORTHEAST-POINTING AIRPLANE
  EMOJI_1_1       = "👫" # MAN AND WOMAN HOLDING HANDS

  DEFAULT_CALENDAR_ID = "primary"

  attr_reader :service, :calendar

  def self.authorize profile_name
    Authorizer.authorize profile_name
  end

  def self.time_range_cast time_or_time_range
    if time_or_time_range.is_a?(Range)
      time_or_time_range.first.beginning_of_day..time_or_time_range.last.end_of_day
    else
      time_or_time_range.beginning_of_day..time_or_time_range.end_of_day
    end
  end

  def self.date_range_cast date_or_date_range
    if date_or_date_range.is_a?(Range)
      date_or_date_range.first.to_date..(date_or_date_range.last + 1.day).to_date
    else
      date_or_date_range.to_date..(date_or_date_range + 1.day).to_date
    end
  end

  def initialize profile_name
    @service = Authorizer.service profile_name
    @calendar = service.get_calendar DEFAULT_CALENDAR_ID
  end

  def find_events time_or_range
    range = CalendarAssistant.time_range_cast time_or_range
    events = service.list_events(DEFAULT_CALENDAR_ID,
                                 time_min: range.first.iso8601,
                                 time_max: range.last.iso8601,
                                 order_by: "startTime",
                                 single_events: true,
                                 max_results: 2000,
                                )
    events&.items || []
  end

  def find_location_events time_or_range
    find_events(time_or_range).select { |e| e.location_event? }
  end

  def create_location_event time_or_range, location
    # find pre-existing events that overlap
    existing_events = find_location_events time_or_range

    # augment event end date appropriately
    range = CalendarAssistant.date_range_cast time_or_range

    deleted_events = []
    modified_events = []

    event = GCal::Event.new start: GCal::EventDateTime.new(date: range.first.iso8601),
                            end: GCal::EventDateTime.new(date: range.last.iso8601),
                            summary: "#{EMOJI_WORLDMAP}  #{location}",
                            transparency: GCal::Event::TRANSPARENCY_NOT_BUSY

    event = service.insert_event DEFAULT_CALENDAR_ID, event

    existing_events.each do |existing_event|
      if existing_event.start.date >= event.start.date && existing_event.end.date <= event.end.date
        service.delete_event DEFAULT_CALENDAR_ID, existing_event.id
        deleted_events << existing_event
      elsif existing_event.start.date <= event.end.date && existing_event.end.date > event.end.date
        existing_event.update! start: GCal::EventDateTime.new(date: range.last)
        service.update_event DEFAULT_CALENDAR_ID, existing_event.id, existing_event
        modified_events << existing_event
      elsif existing_event.start.date < event.start.date && existing_event.end.date >= event.start.date
        existing_event.update! end: GCal::EventDateTime.new(date: range.first)
        service.update_event DEFAULT_CALENDAR_ID, existing_event.id, existing_event
        modified_events << existing_event
      end
    end

    response = {created: [event]}
    response[:deleted] = deleted_events unless deleted_events.empty?
    response[:modified] = modified_events unless modified_events.empty?
    response
  end

  def event_description event, options={}
    attributes = event_attributes(event)
    attributes.delete GCal::Event::Attributes::ACCEPTED # no news is good news
    attributes.delete GCal::Event::Attributes::COMMITMENT # this is meta
    declined = attributes.delete? GCal::Event::Attributes::DECLINED # we'll strike it out in this case
    recurring = attributes.include? GCal::Event::Attributes::RECURRING

    date_wrapper = if event.current?
                     [:bright]
                   elsif event.past?
                     [:faint]
                   else # future
                     []
                   end

    s = sprintf("%-25.25s", event_date_description(event))
    s = date_wrapper.inject(Rainbow(s)) { |text, ansi| text.send ansi }

    s += Rainbow(sprintf(" | %s", event.summary)).bold

    s += Rainbow(sprintf(" (%s)", attributes.to_a.sort.join(", "))).italic unless attributes.empty?

    if options[:verbose] && recurring
      recurrence = IceCube::Schedule.from_ical(event.recurrence_rules(service))
      s += sprintf(" [%s]", recurrence) if recurring
    end

    s = Rainbow(s).strike if declined
    s
  end

  def event_date_description event
    if event.all_day?
      start_date = event.start.ensure_date
      end_date = event.end.ensure_date
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

  #
  #  TODO: make these atributes into methods on Event (possibly taking CalendarAssistant as an arg when necessary)
  #
  def event_attributes event
    Set.new.tap do |attr|
      attr << "not-busy" if event.transparency
      if event.attendees.nil?
        attr << "self"
      else
        event.attendee(calendar.id).tap do |attendee|
          attr << attendee.response_status if attendee&.response_status
        end
      end
      attr << GCal::Event::Attributes::RECURRING if event.recurring_event_id
      if event.attendees && attr.intersect?(Set.new([GCal::Event::Attributes::ACCEPTED, GCal::Event::Attributes::TENTATIVE, GCal::Event::Attributes::NEEDS_ACTION]))
        attr << GCal::Event::Attributes::COMMITMENT
      end
      attr << GCal::Event::Attributes::ONE_ON_ONE if event.attendees&.length == 2
    end
  end
end

require "calendar_assistant/authorizer"
require "calendar_assistant/cli"
require "calendar_assistant/event_extensions"
require "calendar_assistant/rainbow_extensions"
