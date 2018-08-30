describe CalendarAssistant do
  describe ".token_for" do
    it "tests .token_for"
  end
  describe ".save_token_for" do
    it "tests .save_token_for"
  end
  describe ".params_for" do
    it "tests .params_for"
  end
  describe ".calendar_for" do
    it "tests .calendar_for"
  end
  describe ".calendar_list_for" do
    it "tests .calendar_list_for"
  end


  describe "location events" do
    let(:ca) { CalendarAssistant.new("foo@example") }
    let(:calendar) { instance_double("Google::Calendar") }
    let(:new_event) { instance_double("Google::Event") }

    before { allow(ca).to receive(:calendar).and_return(calendar) }

    describe "#create_location_event" do
      before { expect(calendar).to receive(:create_event).and_yield(new_event) }

      context "called with a Time" do
        let(:event_title) { "Palo Alto" }
        let(:event_time) { Chronic.parse("tomorrow") }

        it "creates an appropriately-titled all-day event" do
          expect(new_event).to receive(:title=).with("#{CalendarAssistant::EMOJI_WORLDMAP}  #{event_title}")
          expect(new_event).to receive(:all_day=).with(event_time)

          ca.create_location_event(event_time, event_title)
        end

        context "when there's a pre-existing location event" do
          context "that lasts a single day" do
            it "removes the pre-existing event"
          end

          context "that lasts multiple days" do
            context "when the new event overlaps the start of the pre-existing event" do
              it "shrinks the pre-existing event"
            end

            context "when the new event overlaps the end of the pre-existing event" do
              it "shrinks the pre-existing event"
            end

            context "when the new event is in the middle of the pre-existing event" do
              it "splits the pre-existing event"
            end
          end
        end
      end

      context "called with a Range of Times" do
        let(:event_title) { "Palo Alto" }
        let(:event_start_time) { Chronic.parse("tomorrow") }
        let(:event_end_time) { Chronic.parse("one week from now") }

        it "creates an appropriately-titled multi-day event" do
          expect(new_event).to receive(:title=).with("#{CalendarAssistant::EMOJI_WORLDMAP}  #{event_title}")
          expect(new_event).to receive(:all_day=).with(event_start_time)
          expect(new_event).to receive(:end_time=).with((event_end_time + 1.day).beginning_of_day)

          ca.create_location_event(event_start_time..event_end_time, event_title)
        end

        context "when there's a pre-existing location event" do
          context "that lasts a single day" do
            it "removes the pre-existing event"
          end

          context "that lasts multiple days" do
            context "when the new event overlaps the start of the pre-existing event" do
              it "shrinks the pre-existing event"
            end

            context "when the new event overlaps the end of the pre-existing event" do
              it "shrinks the pre-existing event"
            end

            context "when the new event is in the middle of the pre-existing event" do
              it "splits the pre-existing event"
            end
          end
        end
      end
    end

    describe "#find_location_events" do
      let(:existing_event) { instance_double("Google::Event") }
      let(:existing_location_event) { instance_double("Google::Event") }
      let(:event_time) { Chronic.parse("tomorrow") }

      before do
        allow(existing_event).to receive(:assistant_location_event?) { false }
        allow(existing_location_event).to receive(:assistant_location_event?) { true }
      end

      context "passed a Time" do
        it "fetches only location events for that day" do
          search_start_time = event_time.beginning_of_day
          search_end_time = (event_time + 1.day).beginning_of_day

          expect(calendar).to receive(:find_events_in_range).
                                with(search_start_time, search_end_time, hash_including(max_results: anything)).
                                and_return([existing_event, existing_location_event])

          events = ca.find_location_events(event_time)

          expect(events).to eq([existing_location_event])
        end
      end

      context "passed a Range of Times" do
        it "fetches events for that date range" do
          query_start = event_time - 1.day
          query_end = event_time + 1.day

          search_start_time = query_start.beginning_of_day
          search_end_time = (query_end + 1.day).beginning_of_day

          expect(calendar).to receive(:find_events_in_range).
                                with(search_start_time, search_end_time, hash_including(max_results: anything)).
                                and_return([existing_event, existing_location_event])

          events = ca.find_location_events(query_start..query_end)

          expect(events).to eq([existing_location_event])
        end
      end
    end
  end
end