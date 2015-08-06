#!/usr/bin/env ruby

require 'webrick'
require 'open-uri'
require 'json'
require 'net/http'

class API < WEBrick::HTTPServlet::AbstractServlet

    def do_POST (request, response)
	output=""
	case request.path
		when "/api/v1/supporter/new"
			json = JSON.parse(request.query)
			puts json
			output+="success"
			response.status = 200
			#Net::HTTP.post_form(URI(node["target"]),'input'=>output)
		else
			output+="failure"
			response.status = 404
	end
	response.content_type = "application/json"
	response.body = output+ "\n"
    end
end

if $0 == __FILE__ then
	server = WEBrick::HTTPServer.new(:Port => ENV['API_PORT'])
	server.mount "/", API
	trap("INT") {
		server.shutdown
	}
	server.start
end
