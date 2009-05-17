= bahn

* FIX (url)

== DESCRIPTION:

A library for accessing train information from Deutsche Bahn in an
object-oriented way

== FEATURES

* Exposes Station, Service and Stop objects 
* Does hairy screen-scraping
* Works around bahn.de's crazy transient URLs (provided you don't
  leave objects in scope for 24 hours or so)
  
== BUGS

* This is not an official Deutsche Bahn service, nor does it use an official API;
  it does screen-scraping on their HTML, and is therefore liable to break if Deutsche Bahn
  update their website code.
* Train travel times do not take timezones into account, and may end up 24 hours out
  because whenever it sees a time going 'backwards' (e.g. depart 08:40, arrive 08:20) it
  assumes that just under 24 hours has elapsed. Also, summary timetables for some very long
  distance trains (such as the Trans-Siberian Express) may only show stations that are more
  than 24 hours apart, so there's no way to know that we should be adding on 24 hours to
  the time.

== SYNOPSIS:

 require 'bahn'
 ulm = Bahn::Station.find(:first, :name => 'Ulm')
  #=> #<Bahn::Station:0x55fb4 @id=8000170, @y_coord="48399019", @name="Ulm Hbf", @x_coord="9982161">
 my_train = ulm.departures(:include => :ice).find{|departure| departure.service.name == 'ICE 699'}
  #=> #<Bahn::Stop @time=07:55 @station="Ulm Hbf" @destination="M\303\274nchen Hbf">
 my_train.destination.arrival_time
  #=> 09:17

== INSTALL:

* sudo gem install bahn

== LICENSE:

(The MIT License)

Copyright (c) 2009 Matthew Westcott

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
