#
#  this file extends the Google::Event class found in the "google_calendar" rubygem
#

require "google_calendar"

module Google
  class Event
    def assistant_location_event?
      title =~ /^#{CalendarAssistant::EMOJI_WORLDMAP}/
    end

    def to_assistant_s
      if assistant_location_event?
        if Event.parse_time(end_time) - Event.parse_time(start_time) <= 1.day
          sprintf "%-23.23s |                         | %-40.40s",
                  Event.assistant_date(Event.parse_time(start_time)), title
        else
          sprintf "%-23.23s | %-23.23s | %-40.40s",
                  Event.assistant_date(Event.parse_time(start_time)),
                  Event.assistant_date(Event.parse_time(end_time) - 1.day), title
        end
      else
        sprintf "%23.23s | %23.23s | %-40.40s",
                Event.assistant_time(Event.parse_time(start_time)),
                Event.assistant_time(Event.parse_time(end_time)), title
      end
    end

    private

    def self.assistant_time t
      t.getlocal.strftime("%Y-%m-%d %H:%M:%S %Z")      
    end

    def self.assistant_date t
      t.getlocal.strftime("%Y-%m-%d %a")
    end
  end
end