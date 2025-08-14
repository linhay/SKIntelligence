//
//  File.swift
//  SKIntelligence
//
//  Created by linhey on 7/1/25.
//

import Foundation
import SKIntelligence
import JSONSchemaBuilder
import EventKit

public struct SKIToolQueryCalendar: SKITool {
  
    public let name: String = "query_calendar_events"
    public let description: String = """
                    Query events from the user's system calendars for a specific date or date range. 
                    The date range cannot exceed 7 consecutive days. Results will be returned in the user's local time format.
                    You need to convert user provided dates to the required format.
        """
    
    @Schemable
    public struct Arguments {
        @SchemaOptions(.description(
            """
            The start date for the query in ISO 8601 format (YYYY-MM-DD). 
            This date should be provided in UTC and will be converted to the user's local timezone.
            """))
        public let start_date: String
        @SchemaOptions(.description(
            """
            Optional end date for the query in ISO 8601 format (YYYY-MM-DD). If not provided, 
            only events on the start date will be returned. The date range cannot exceed 7 days.
            This date should be provided in UTC and will be converted to the user's local timezone.
            """))
        public let end_date: String
        @SchemaOptions(.description(
            """
            Whether to include all-day events in the results. 
            If true, all-day events will be included; if false, only timed events will be returned.
            """))
        public let include_all_day_events: Bool
    }
    
    @Schemable
    public struct Event: Codable {
        @SchemaOptions(.description("The title of the calendar event."))
        public let title: String
        @SchemaOptions(.description("The start date of the event in ISO 8601 format (YYYY-MM-DDTHH:mm:ssZ)."))
        public let startDate: String
        @SchemaOptions(.description("The end date of the event in ISO 8601 format (YYYY-MM-DDTHH:mm:ssZ)."))
        public let endDate: String
        @SchemaOptions(.description("The location of the event, if available."))
        public let location: String?
        @SchemaOptions(.description("Indicates whether the event is an all-day event."))
        public let isAllDay: Bool
        
        public static func convert(event: EKEvent) -> Event {
            Event(
                title: event.title ?? "Untitled",
                startDate: ISO8601DateFormatter().string(from: event.startDate),
                endDate: ISO8601DateFormatter().string(from: event.endDate),
                location: event.location,
                isAllDay: event.isAllDay
            )
        }
        
    }
    
    @Schemable
    public struct ToolOutput: Codable {
        @SchemaOptions(.description("A list of calendar events that match the query criteria."))
        public let events: [Event]
    }
    
    public enum Errors: Error {
     case accessDenied
    }
    
    public init() {}
    
    public func call(_ arguments: Arguments) async throws -> ToolOutput {
        let store = EKEventStore()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if try await store.requestFullAccessToEvents(),
           let startDate = formatter.date(from: arguments.start_date),
           let endDate = arguments.end_date.isEmpty ? nil : formatter.date(from: arguments.end_date) {
            let predicate = store.predicateForEvents(withStart: startDate,
                                                     end: endDate,
                                                     calendars: nil)
            let events = store.events(matching: predicate)
            return .init(events: events.map(Event.convert(event:)))
        } else {
            throw Errors.accessDenied
        }
    }
    
}
