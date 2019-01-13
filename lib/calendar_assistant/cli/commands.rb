require "calendar_assistant/cli/helpers"

class CalendarAssistant
  module CLI
    class Commands < Thor
      def self.will_create_a_service
        option CalendarAssistant::Config::Keys::Settings::PROFILE,
               type: :string,
               desc: "the profile you'd like to use (if different from default)",
               aliases: ["-p"]

        option CalendarAssistant::Config::Keys::Options::LOCAL_STORE,
               type: :string,
               banner: "FILENAME",
               desc: "Load events from a local file instead of Google Calendar"
      end

      def self.has_attendees
        option CalendarAssistant::Config::Keys::Options::ATTENDEES,
               type: :string,
               banner: "ATTENDEE1[,ATTENDEE2[,...]]",
               desc: "[default 'me'] people (email IDs) to whom this command will be applied",
               aliases: ["-a"]
      end

      default_config = CalendarAssistant::CLI::Config.new options: options # used in option descriptions

      class_option :help,
                   type: :boolean,
                   aliases: ["-h", "-?"]
      class_option CalendarAssistant::Config::Keys::Options::DEBUG,
                   type: :boolean,
                   desc: "how dare you suggest there are bugs"

      class_option CalendarAssistant::Config::Keys::Options::FORMATTING,
                   type: :boolean,
                   desc: "Enable Text Formatting",
                   default: CalendarAssistant::Config::DEFAULT_SETTINGS[CalendarAssistant::Config::Keys::Options::FORMATTING]

      desc "version",
           "Display the version of calendar-assistant"

      def version
        return if handle_help_args
        out.puts CalendarAssistant::VERSION
      end


      desc "config",
           "Dump your configuration parameters (merge of defaults and overrides from #{CalendarAssistant::CLI::Config::CONFIG_FILE_PATH})"

      def config
        return if handle_help_args
        settings = CalendarAssistant::CLI::Config.new.settings
        out.puts TOML::Generator.new({CalendarAssistant::Config::Keys::SETTINGS => settings}).body
      end


      desc "setup",
           "Link your local calendar-assistant installation to a Google API Client"
      long_desc <<~EOD
      This command will walk you through setting up a Google Cloud
      Project, enabling the Google Calendar API, and saving the
      credentials necessary to access the API on behalf of users.

      If you already have downloaded client credentials, you don't
      need to run this command. Instead, rename the downloaded JSON
      file to `#{CalendarAssistant::CLI::Authorizer::CREDENTIALS_PATH}`
      EOD

      def setup
        # TODO ugh see #34 for advice on how to clean this up
        return if handle_help_args
        if File.exist? CalendarAssistant::CLI::Authorizer::CREDENTIALS_PATH
          out.puts sprintf("Credentials already exist in %s",
                           CalendarAssistant::CLI::Authorizer::CREDENTIALS_PATH)
          return
        end

        out.launch "https://developers.google.com/calendar/quickstart/ruby"
        sleep 1
        out.puts <<~EOT
        Please click on "ENABLE THE GOOGLE CALENDAR API" and either create a new project or select an existing project.

        (If you create a new project, name it something like "yourname-calendar-assistant" so you remember why it exists.)

        Then click "DOWNLOAD CLIENT CONFIGURATION" to download the credentials to local disk.

        Finally, paste the contents of the downloaded file here (it should be a complete JSON object):
        EOT

        json = out.prompt "Paste JSON here"
        File.open(CalendarAssistant::CLI::Authorizer::CREDENTIALS_PATH, "w") do |f|
          f.write json
        end
        FileUtils.chmod 0600, CalendarAssistant::CLI::Authorizer::CREDENTIALS_PATH

        out.puts "\nOK! Your next step is to run `calendar-assistant authorize`."
      end


      desc "authorize PROFILE_NAME",
           "create (or validate) a profile named NAME with calendar access"
      long_desc <<~EOD
      Create and authorize a named profile (e.g., "work", "home",
      "flastname@company.tld") to access your calendar.

      When setting up a profile, you'll be asked to visit a URL to
      authenticate, grant authorization, and generate and persist an
      access token.

      In order for this to work, you'll need to have set up your API client
      credentials. Run `calendar-assistant help setup` for instructions.
      EOD

      def authorize profile_name = nil
        return if handle_help_args
        return help! if profile_name.nil?

        get_authorizer(profile_name: profile_name).authorize

        puts "\nYou're authorized!\n\n"
      end


      desc "show [DATE | DATERANGE | TIMERANGE]",
           "Show your events for a date or range of dates (default 'today')"
      option CalendarAssistant::Config::Keys::Options::COMMITMENTS,
             type: :boolean,
             desc: "only show events that you've accepted with another person",
             aliases: ["-c"]
      will_create_a_service
      has_attendees

      def show datespec = "today"
        calendar_assistant(datespec) do |ca, date|
          event_set = ca.find_events date
          out.print_events ca, event_set
        end
      end


      desc "join [TIME]",
           "Open the URL for a video call attached to your meeting at time TIME (default 'now')"
      option CalendarAssistant::Config::Keys::Options::JOIN,
             type: :boolean, default: true,
             desc: "launch a browser to join the video call URL"
      will_create_a_service

      def join timespec = "now"
        return if handle_help_args
        set_formatting
        ca = CalendarAssistant.new get_config, service: service
        ca.in_env do
          event_set, url = CalendarAssistant::CLI::Helpers.find_av_uri ca, timespec
          if !event_set.empty?
            out.print_events ca, event_set
            out.puts url
            out.launch url if options[CalendarAssistant::Config::Keys::Options::JOIN]
          else
            out.puts "Could not find a meeting '#{timespec}' with a video call to join."
          end
        end
      end


      desc "location [DATE | DATERANGE]",
           "Show your location for a date or range of dates (default 'today')"
      will_create_a_service

      def location datespec = "today"
        calendar_assistant(datespec) do |ca, date|
          event_set = ca.find_location_events date
          out.print_events ca, event_set
        end
      end


      desc "location-set LOCATION [DATE | DATERANGE]",
           "Set your location to LOCATION for a date or range of dates (default 'today')"
      will_create_a_service

      def location_set location = nil, datespec = "today"
        return help! if location.nil?

        calendar_assistant(datespec) do |ca, date|
          event_set = ca.create_location_event date, location
          out.print_events ca, event_set
        end
      end


      desc "availability [DATE | DATERANGE | TIMERANGE]",
           "Show your availability for a date or range of dates (default 'today')"
      option CalendarAssistant::Config::Keys::Settings::MEETING_LENGTH,
             type: :string,
             banner: "LENGTH",
             desc: sprintf("[default %s] find chunks of available time at least as long as LENGTH (which is a ChronicDuration string like '30m' or '2h')",
                           default_config.setting(CalendarAssistant::Config::Keys::Settings::MEETING_LENGTH)),
             aliases: ["-l"]
      option CalendarAssistant::Config::Keys::Settings::START_OF_DAY,
             type: :string,
             banner: "TIME",
             desc: sprintf("[default %s] find chunks of available time after TIME (which is a BusinessTime string like '9am' or '14:30')",
                           default_config.setting(CalendarAssistant::Config::Keys::Settings::START_OF_DAY)),
             aliases: ["-s"]
      option CalendarAssistant::Config::Keys::Settings::END_OF_DAY,
             type: :string,
             banner: "TIME",
             desc: sprintf("[default %s] find chunks of available time before TIME (which is a BusinessTime string like '9am' or '14:30')",
                           default_config.setting(CalendarAssistant::Config::Keys::Settings::END_OF_DAY)),
             aliases: ["-e"]
      has_attendees
      will_create_a_service

      def availability datespec = "today"
        calendar_assistant(datespec) do |ca, date|
          event_set = ca.availability date
          out.print_available_blocks ca, event_set
        end
      end

      private

      def set_formatting
        Rainbow.enabled = !!options[:formatting]
      end

      def service
        @service ||= begin
          if filename = get_config.setting(Config::Keys::Options::LOCAL_STORE)
            CalendarAssistant::LocalService.new(file: filename)
          else
            get_authorizer.service
          end
        end
      end

      def get_authorizer(profile_name: get_config.profile_name, token_store: get_config.token_store)
        @authorizer ||= {}
        @authorizer[profile_name] ||= Authorizer.new(profile_name, token_store)
      end

      def calendar_assistant datespec = "today"
        return if handle_help_args
        set_formatting
        ca = CalendarAssistant.new(get_config, service: service)
        ca.in_env do
          yield(ca, CalendarAssistant::CLI::Helpers.parse_datespec(datespec))
        end
      end

      def get_config
        @config ||= CalendarAssistant::CLI::Config.new(options: options)
      end

      def out
        @out ||= CalendarAssistant::CLI::Printer.new
      end

      def help!
        help(current_command_chain.first)
      end

      def handle_help_args
        if options[:help]
          help!
          return true
        end
      end
    end
  end
end
