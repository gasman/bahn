require 'open-uri'
require 'json'
require 'iconv'
require 'hpricot'
require 'cgi'

module Bahn
	def self.autocomplete_query(term)
		uri = "http://reiseauskunft.bahn.de/bin/ajax-getstop.exe/en?REQ0JourneyStopsS0A=1&REQ0JourneyStopsS0G=#{CGI.escape(term.to_s)}"
		io = open(uri)
		response_text = Iconv.iconv('utf-8', io.charset, io.read).first
		response_json = JSON.parse(response_text.scan(/\{.*\}/).first)
		response_json['suggestions']
	end
	
	class ClockTime < Time
		# represents a time without a date
		def self.clock(hours, mins)
			self.utc(1970, 1, 1, hours, mins, 0)
		end
		
		def self.parse(str)
			if str =~ /(\d+):(\d+)/ then self.utc(1970, 1, 1, $1, $2, 0) end
		end
		
		def inspect
			to_s
		end
		def to_s
			sprintf("%02d:%02d", hour, min)
		end
	end
	
	class Station
		def self.find(id_or_type, opts = {})
			case id_or_type
				when :first
					query = Bahn.autocomplete_query(opts[:name])
					query.size ? self.new(:autocomplete_result => query.first) : nil
				when :all
					query = Bahn.autocomplete_query(opts[:name])
					query.collect {|result| self.new(:autocomplete_result => result)}
				else # assume a numeric ID
					self.new(:id => id_or_type)
			end
		end
		
		def initialize(opts)
			if opts[:autocomplete_result]
				populate_from_autocomplete_result(opts[:autocomplete_result])
			else
				@id = opts[:id].to_i
				@name = opts[:name]
				@x_coord = opts[:x_coord]
				@y_coord = opts[:y_coord]
			end
		end
		
		attr_reader :id

		def name
			fetch_autocomplete_result if @name.nil?
			@name
		end

		def x_coord
			fetch_autocomplete_result if @x_coord.nil?
			@x_coord
		end

		def y_coord
			fetch_autocomplete_result if @y_coord.nil?
			@y_coord
		end
		
		def departures(opts = {})
			DepartureBoard.new(self, opts)
		end
		
		# =====
		private
		# =====
		def fetch_autocomplete_result
			populate_from_autocomplete_result(Bahn.autocomplete_query(@id).first)
		end

		def populate_from_autocomplete_result(autocomplete_data)
			@id = autocomplete_data['id'].scan(/\@L=(\d+)\@/).first.first.to_i
			@name = autocomplete_data['id'].scan(/\@O=([^\@]*)\@/).first.first
			@x_coord = autocomplete_data['xcoord']
			@y_coord = autocomplete_data['ycoord']
		end
	end
	
	class DepartureBoard
		TRANSPORT_TYPES = {
			:ice =>0x100,
			:ic_ec => 0x80,
			:ir => 0x40,
			:regional => 0x20,
			:urban => 0x10,
			:bus => 0x08,
			:boat => 0x04,
			:subway => 0x02,
			:tram => 0x01
		}
		include Enumerable
		def initialize(station, opts)
			@station = station
			
			transport_types = Array(opts[:include] || TRANSPORT_TYPES.keys) - Array(opts[:exclude])
			filter_num = transport_types.inject(0) {|sum, type| sum + (TRANSPORT_TYPES[type] || 0) }
			filter = sprintf("%09b", filter_num)
			@url_prefix = "http://reiseauskunft.bahn.de/bin/bhftafel.exe/en?input=#{station.id}&productsFilter=#{filter}&start=1&boardType=dep&dateBegin=14.12.08&dateEnd=12.12.09&time=00:00"
			@departure_pages = []
		end
		
		def each
			0.upto(23) do |hour|
				doc = departure_page(hour)
				# find all tr children of table.result which contain a td.train
				# and do not have class 'browse'
				departure_docs = doc / 'table.result tr[td.train]:not(.browse)'
				departure_docs.each do |departure_doc|
					service_link = departure_doc % 'td.train:nth-child(1) a'
					destination_link = departure_doc % 'td.route span.bold a'
					(destination_id, destination_time_string), = destination_link['onclick'].scan(/^sHC\(this, '', '(\d+)','([^']*)'\)/)
					destination_time = ClockTime.parse(destination_time_string)

					intermediate_stops =  (departure_doc % 'td.route').children.find_all{|node| node.text?}.join(' ')
					departure_time = ClockTime.parse((departure_doc % 'td.time').inner_text)
					last_time = departure_time
					days_passed = 0

					intermediate_stops.scan(/\d+:\d+/) do |time_string|
						time = ClockTime.parse(time_string)
						days_passed += 1 if time < last_time
						last_time = time
					end
					inferred_time_to_destination = days_passed * 24*60*60 + (destination_time - departure_time)
					
					platform_td = departure_doc % 'td.platform'
					if platform_td.nil?
						platform = :none
					else
						platform = platform_td.inner_text.strip
					end

					yield Stop.new(
						:station => @station,
						:service => Service.new(
							:path => service_link['href'].sub(/\?.*/, ''),
							:name => service_link.inner_text.strip.gsub(/\s+/, ' '),
							:destination_info => {
								:station => Station.new(
									:id => destination_id,
									:name => destination_link.inner_text.strip
								),
								:arrival_time => destination_time
							}
						),
						:departure_time => departure_time,
						:platform => (platform == '' ? :none : platform),
						:inferred_time_to_destination => inferred_time_to_destination
					)
				end
			end
		end
		
		# =====
		private
		# =====
		def departure_page(hour)
			@departure_pages[hour] ||= Hpricot(open("#{@url_prefix}%2B#{hour * 60}"))
		end
	end
	
	class Service
		def initialize(opts)
			@path = opts[:path]
			@name = opts[:name]
			if opts[:origin_info]
				@origin = Stop.new(opts[:origin_info].merge(
					:service => self,
					:arrival_time => :none,
					:arrival_time_from_origin => :none,
					:arrival_time_to_destination => :none,
					:departure_time_from_origin => 0
				))
			end
			if opts[:destination_info]
				@destination = Stop.new(opts[:destination_info].merge(
					:service => self,
					:arrival_time_to_destination => 0,
					:departure_time => :none,
					:departure_time_from_origin => :none,
					:departure_time_to_destination => :none
				))
			end
		end
		
		def stops
			if !@stops
				stop_docs = traininfo_response_doc / "table.result tr[td.station]"
				last_time = nil
				days_passed = 0
				
				origin_departure_time = nil
				
				@stops = stop_docs.collect {|stop_doc|
					station_link = stop_doc % 'td.station a'
					
					arrival_time = ClockTime.parse((stop_doc % 'td.arrival').inner_text)
					departure_time = ClockTime.parse((stop_doc % 'td.departure').inner_text)
					origin_departure_time ||= departure_time
					
					if arrival_time.nil?
						arrival_time_from_origin = :none
					else
						days_passed += 1 if (!last_time.nil? && arrival_time < last_time)
						arrival_time_from_origin = days_passed * 24*60*60 + (arrival_time - origin_departure_time)
						last_time = arrival_time
					end
					
					if departure_time.nil?
						departure_time_from_origin = :none
					else
						days_passed += 1 if (!last_time.nil? && departure_time < last_time)
						departure_time_from_origin = days_passed * 24*60*60 + (departure_time - origin_departure_time)
						last_time = departure_time
					end
	
					platform = (stop_doc % 'td.platform').inner_text.strip

					Stop.new(
						:station => Station.new(
							:id => station_link['href'].scan(/&input=[^&]*%23(\d+)&/).first.first,
							:name => station_link.inner_text
						),
						:service => self,
						:arrival_time => arrival_time || :none,
						:departure_time => departure_time || :none,
						:platform => (platform == '' ? :none : platform),
						:arrival_time_from_origin => arrival_time_from_origin,
						:departure_time_from_origin => departure_time_from_origin
					)
				}
			end
			@stops
		end
		
		def origin
			@origin ||= stops.first
		end

		def destination
			@destination ||= stops.last
		end
		
		def inspect
			"#<#{self.class} @name=#{@name.inspect} @origin=#{@origin.inspect} @destination=#{@destination.inspect}>"
		end
		
		# =====
		private
		# =====
		def traininfo_response_doc
			@traininfo_response_doc ||= Hpricot(open("http://reiseauskunft.bahn.de#{@path}"))
		end
	end
	
	class Stop
		def initialize(opts)
			# for the following fields, use :none to mean none supplied (as opposed to not fetched yet):
			# @arrival_time, @departure_time, @platform, @arrival_time_from_origin, @departure_time_from_origin

			@station = opts[:station] # required
			@service = opts[:service] # required
			@arrival_time = opts[:arrival_time]
			@departure_time = opts[:departure_time] # arrival_time or departure_time is required
			@platform = opts[:platform]
			@arrival_time_from_origin = opts[:arrival_time_from_origin]
			@departure_time_from_origin = opts[:departure_time_from_origin]

			@inferred_time_to_destination = opts[:inferred_time_to_destination]
			
			# these can be calculated from arrival_time_from_origin and departure_time_from_origin
			# (but require service.origin, and therefore service.stops, to have been looked up)
			@arrival_time_to_destination = opts[:arrival_time_to_destination]
			@departure_time_to_destination = opts[:departure_time_to_destination]
		end
		
		attr_reader :station, :service
		
		def platform
			get_full_details if @platform.nil?
			@platform == :none ? nil : @platform
		end
		
		def arrival_time
			get_full_details if @arrival_time.nil?
			@arrival_time == :none ? nil : @arrival_time
		end

		def departure_time
			get_full_details if @departure_time.nil?
			@departure_time == :none ? nil : @departure_time
		end
		
		def arrival_time_from_origin
			get_full_details if @arrival_time_from_origin.nil?
			@arrival_time_from_origin == :none ? nil : @arrival_time_from_origin
		end
		
		def departure_time_from_origin
			get_full_details if @departure_time_from_origin.nil?
			@departure_time_from_origin == :none ? nil : @departure_time_from_origin
		end
		
		def arrival_time_to_destination
			if @arrival_time_to_destination.nil?
				if arrival_time_from_origin == :none
					@arrival_time_to_destination == :none
				else
					@arrival_time_to_destination = @service.destination.arrival_time_from_origin - arrival_time_from_origin
				end
			end
			@arrival_time_to_destination
		end

		def departure_time_to_destination
			if @departure_time_to_destination.nil?
				if departure_time_from_origin == :none
					@departure_time_to_destination == :none
				else
					@departure_time_to_destination = @service.destination.arrival_time_from_origin - departure_time_from_origin
				end
			end
			@departure_time_to_destination
		end
		
		def inferred_time_to_destination
			@inferred_time_to_destination ||= departure_time_to_destination || arrival_time_to_destination
		end

		def inspect
			"#<#{self.class} @time=#{(@departure_time.nil? || @departure_time == :none ? @arrival_time : @departure_time).inspect} @station=#{@station.name.inspect} @destination=#{service.destination.station.name.inspect}>"
		end

		# =====
		private
		# =====
		def get_full_details
			if @arrival_time and @arrival_time != :none
				stop = @service.stops.find {|stop|
					stop.station.id == @station.id && stop.arrival_time == @arrival_time
				}
				@departure_time = stop.departure_time || :none
			else
				stop = @service.stops.find {|stop|
					stop.station.id == @station.id && stop.departure_time == @departure_time
				}
				@arrival_time = stop.arrival_time || :none
			end
			@platform = stop.platform || :none
			@arrival_time_from_origin = stop.arrival_time_from_origin || :none
			@departure_time_from_origin = stop.departure_time_from_origin || :none
		end
	end
end
