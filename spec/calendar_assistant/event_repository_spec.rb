require 'date'

describe CalendarAssistant::EventRepository do

  let(:service) { FakeService.new }
  let(:event_repository) {described_class.new(service, "primary")}

  let(:calendar_id) { "primary" }
  let(:event_array) { [nine_event, nine_thirty_event] }

  let(:nine_event) { GCal::Event.new(id: 1, start: GCal::EventDateTime.new(date_time: Time.parse("2018-10-18 09:00:00")), end: GCal::EventDateTime.new(date_time: Time.parse("2018-10-18 10:00:00"))) }
  let(:nine_thirty_event) { GCal::Event.new(id: 2, start: GCal::EventDateTime.new(date_time: Time.parse("2018-10-18 09:30:00")), end: GCal::EventDateTime.new(date_time: Time.parse("2018-10-18 10:00:00"))) }

  before do
    event_array.each do |event|
      service.insert_event("primary", event)
    end
  end

  let(:time_range) {Time.parse("2018-10-18")..Time.parse("2018-10-19")}

  describe "#find" do
    it "sets some basic query options" do
      result = event_repository.find time_range
      expect(result).to eq(event_array)
    end

    context "given a time range" do
      it "calls CalendarService#list_events with the range" do
        result = event_repository.find time_range
        expect(result).to eq(event_array)
      end
    end

    context "when no items are found" do
      let(:time_range) {Time.parse("2017-10-18")..Time.parse("2017-10-19")}

      it "returns an empty array" do
        result = event_repository.find time_range
        expect(result).to eq([])
      end
    end
  end

  describe "#delete" do
    it "calls the service with the event id" do
      event_repository.delete(nine_event)
      result = event_repository.find time_range
      expect(result).to eq([nine_thirty_event])
    end
  end

  describe "#update" do
    let(:time_range) {Time.parse("2018-10-18 08:00")..Time.parse("2018-10-18 09:15")}

    it "casts dates to GCal::EventDateTime and updates the event" do
      new_attributes = { start: DateTime.parse("1776-07-04") }
      event_repository.update(nine_event, new_attributes)

      result = event_repository.find time_range
      expect(result[0].start.date).to eq "1776-07-04T00:00:00+00:00"
    end
  end
end
