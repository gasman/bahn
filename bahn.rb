require 'open-uri'
require 'json'
require 'iconv'
require 'hpricot'
require 'cgi'

module Bahn
	def self.autocomplete_query(term)
		uri = "http://reiseauskunft.bahn.de/bin/ajax-getstop.exe/en?REQ0JourneyStopsS0A=1&REQ0JourneyStopsS0G=#{CGI.escape(term)}"
		io = open(uri)
		response_text = Iconv.iconv('utf-8', io.charset, io.read).first
		response_json = JSON.parse(response_text.scan(/\{.*\}/).first)
		response_json['suggestions']
	end
	
	class ClockTime
		include Comparable

		# represents an offset past midnight on a non-specific date, counted in days, hours and minutes
		def initialize(days = 0, hours = 0, minutes = 0)
			@days = days
			@hours = hours
			@minutes = minutes
		end
		
		attr_reader :days, :hours, :minutes
		
		def to_s
			out = sprintf("%02d:%02d", @hours, @minutes)
			if @days == 1
				out << " +1 day"
			elsif @days > 1
				out << " +#{@days} days"
			end
			out
		end
		
		def <=>(other)
			[@days, @hours, @minutes] <=> [other.days, other.hours, other.minutes]
		end
		
		def to_seconds
			((@days * 24 + @hours) * 60 + @minutes) * 60
		end
		
		def +(seconds)
			ClockTime.seconds(self.to_seconds + seconds)
		end

		def -(other_time)
			self.to_seconds - other_time.to_seconds
		end
		
		def self.seconds(s)
			minutes = s / 60
			hours = minutes / 60
			days = hours / 24
			self.new(days, hours % 24, minutes % 24)
		end
		
		def self.parse(str, opts = {})
			case str
				when /(\d+):(\d+) \+(\d+) day/
					return self.new($3.to_i, $1.to_i, $2, to_i)
				when /(\d+):(\d+)/
					hours = $1.to_i
					mins = $2.to_i
					if opts[:after]
						if ([hours, mins] <=> [opts[:after].hours, opts[:after].minutes]) == -1
							# new date appears to be 'before' the after date, so add 1 day
							return self.new(opts[:after].days + 1, hours, mins)
						else
							return self.new(opts[:after].days, hours, mins)
						end
					else
						return self.new(0, hours, mins)
					end
				else
					return nil
			end
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
				@id = opts[:id]
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
		
		def departures
			DepartureBoard.new("http://reiseauskunft.bahn.de/bin/bhftafel.exe/en?input=#{@id}&productsFilter=1111100000&start=1&boardType=dep&dateBegin=14.12.08&dateEnd=12.12.09&time=00:00")
		end
		
		# =====
		private
		# =====
		def fetch_autocomplete_result
			populate_from_autocomplete_result(Bahn.autocomplete_query(@id).first)
		end

		def populate_from_autocomplete_result(autocomplete_data)
			@id = autocomplete_data['id'].scan(/\@L=(\d+)\@/).first.first
			@name = autocomplete_data['id'].scan(/\@O=([^\@]*)\@/).first.first
			@x_coord = autocomplete_data['xcoord']
			@y_coord = autocomplete_data['ycoord']
		end
	end
	
	class DepartureBoard
		include Enumerable
		def initialize(url_prefix)
			@url_prefix = url_prefix
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
					(destination_id, arrival_time), = destination_link['onclick'].scan(/^sHC\(this, '', '(\d+)','([^']*)'\)/)
					intermediate_stops =  (departure_doc % 'td.route').children.find_all{|node| node.text?}.join(' ')
					departure_time = ClockTime.parse((departure_doc % 'td.time').inner_text)
					last_time = departure_time
					intermediate_stops.scan(/\d+:\d+/) do |time|
						last_time = ClockTime.parse(time, :after => last_time)
					end
					arrival_time = ClockTime.parse(arrival_time, :after => last_time)

					yield Departure.new(
						:time => departure_time,
						:service_name => service_link.inner_text.strip.gsub(/\s+/, ' '),
						:service_path => service_link['href'].sub(/\?.*/, ''),
						:destination_name => destination_link.inner_text.strip,
						:destination_id => destination_id,
						:arrival_time => arrival_time
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
	
	class Departure
		def initialize(opts)
			@time = opts[:time]
			@service_name = opts[:service_name]
			@service_path = opts[:service_path]
			@destination_name = opts[:destination_name]
			@destination_id = opts[:destination_id]
			@arrival_time = opts[:arrival_time]
		end

		attr_reader :time, :service_name, :destination_name, :destination_id, :arrival_time
		
		def destination
			@destination ||= Station.new(:id => @destination_id, :name => @destination_name)
		end
		
		def service
			@service ||= Service.new(
				:path => @service_path,
				:name => @service_name,
				:destination => destination,
				:arrival_time => @arrival_time
			)
		end
		
		def to_s
			"#{service_name} #{@time} #{@destination_name}"
		end
	end

	class Service
		def initialize(opts)
			@path = opts[:path]
			@name = opts[:name]
			@destination = opts[:destination]
			@arrival_time = opts[:arrival_time]
		end
		
		def stops
			stop_docs = traininfo_response_doc / "table.result tr[td.station]"
			last_time = nil
			stop_docs.collect {|stop_doc|
				station_link = stop_doc % 'td.station a'

				arrival_time = ClockTime.parse((stop_doc % 'td.arrival').inner_text, :after => last_time)
				last_time = arrival_time unless arrival_time.nil?

				departure_time = ClockTime.parse((stop_doc % 'td.departure').inner_text, :after => last_time)
				last_time = departure_time unless departure_time.nil?

				platform = (stop_doc % 'td.platform').inner_text.strip
				Stop.new(
					:station_name => station_link.inner_text,
					:station_id => station_link['href'].scan(/&input=[^&]*%23(\d+)&/).first.first,
					:arrival_time => arrival_time,
					:departure_time => departure_time,
					:platform => (platform == '' ? nil : platform)
				)
			}
		end
		
		class Stop
			def initialize(opts)
				@station_name = opts[:station_name]
				@station_id = opts[:station_id]
				@arrival_time = opts[:arrival_time]
				@departure_time = opts[:departure_time]
				@platform = opts[:platform]
			end

			attr_reader :station_name, :station_id, :arrival_time, :departure_time, :platform
			
			def station
				Station.new(:id => @station_id, :name => @station_name)
			end
		end
		
		# =====
		private
		# =====
		def traininfo_response_doc
			@traininfo_response_doc ||= Hpricot(open("http://reiseauskunft.bahn.de#{@path}"))
		end
	end
end
