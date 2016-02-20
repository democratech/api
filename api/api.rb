# encoding: utf-8

module Democratech
	class API < Grape::API
		prefix 'api'
		format :json
		class << self
			attr_accessor :db, :mg_client, :mandrill
		end

		get do
			# DO NOT DELETE used to test the api is live
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
		end

		mount ::Democratech::WufooV2
		mount ::Democratech::StripeV2
		mount ::Democratech::SupporteursV1
		mount ::Democratech::StripeV1
		mount ::Democratech::WufooV1
		mount ::Democratech::EmailV1
	end
end
