# encoding: utf-8

=begin
    democratech API synchronizes the various Web services democratech uses
    Copyright (C) 2015,2016  Thibauld Favre

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
=end

module Democratech
	class API < Grape::API
		class << self
			attr_accessor :pg, :aws, :log, :twilio, :authy, :mailer
		end

		get do
			# DO NOT DELETE used to test the api is live
			API.log.debug "API test OK"
			return {"api"=>"ok"}
		end

		helpers do
			def slack_notification(msg,channel="supporteurs",icon=":ghost:",from="democratech",attachment=nil)
				uri = URI.parse(SLCKHOST)
				http = Net::HTTP.new(uri.host, uri.port)
				http.use_ssl = true
				http.verify_mode = OpenSSL::SSL::VERIFY_NONE
				request = Net::HTTP::Post.new(SLCKPATH)
				msg={
					"channel"=> channel,
					"username"=> from,
					"text"=> msg,
					"icon_emoji"=>icon
				}
				if attachment then
					msg["attachments"]=[{
						"fallback"=>attachment["fallback"]
					}]
					msg["attachments"][0]["color"]=attachment["color"] if attachment["color"]
					msg["attachments"][0]["pretext"]=attachment["pretext"] if attachment["pretext"]
					msg["attachments"][0]["title"]=attachment["title"] if attachment["title"]
					msg["attachments"][0]["title_link"]=attachment["title_link"] if attachment["title_link"]
					msg["attachments"][0]["text"]=attachment["text"] if attachment["text"]
					msg["attachments"][0]["image_url"]=attachment["image_url"] if attachment["image_url"]
					msg["attachments"][0]["thumb_url"]=attachment["image_url"] if attachment["thumb_url"]
				end
				request.body = "payload="+JSON.dump(msg)
				res=http.request(request)
				if not res.kind_of? Net::HTTPSuccess then
					puts "An error occurred trying to send a Slack notification\n"
				end
			end

			def slack_notifications(notifs)
				channels={}
				notifs.each do |n|
					msg=n[0] || ""
					chann=n[1] || "errors"
					icon=n[2] || ":warning:"
					from=n[3] || "democratech"
					if channels[chann].nil? then
						channels[chann]="%s *%s* %s" % [icon,from,msg]
					else
						channels[chann]+="\n%s *%s* %s" % [icon,from,msg]
					end
				end
				channels.each do |k,v|
					slack_notification(v,k,":bell:","democratech")
				end
			end

			def pg_connect()
				if ::DEBUG then
					API.pg=PG.connect(
						"dbname"=>PGNAME_TEST,
						"user"=>PGUSER_TEST,
						"password"=>PGPWD_TEST,
						"host"=>PGHOST,
						"port"=>PGPORT
					)
				else
					API.pg=PG.connect(
						"dbname"=>PGNAME,
						"user"=>PGUSER,
						"password"=>PGPWD,
						"host"=>PGHOST,
						"port"=>PGPORT
					)
				end
			end

			def pg_close()
				API.pg.close unless API.pg.nil?
			end
		end

		mount ::Democratech::WufooV3
		mount ::Democratech::PaymentV1
		mount ::Democratech::AuthV2
		mount ::Democratech::AuthV1
		mount ::Democratech::VoteV1
		mount ::Democratech::WufooV2
		mount ::Democratech::StripeV2
		mount ::Democratech::SupporteursV1
		mount ::Democratech::StripeV1
		mount ::Democratech::WufooV1
		mount ::Democratech::EmailV1
		mount ::Democratech::CandidatV1
		mount ::Democratech::AppV1
		mount ::Democratech::CitizenV1
	end
end
