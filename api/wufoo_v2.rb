# encoding: utf-8

module Democratech
	class WufooV2 < Grape::API
		prefix 'api'
		version ['v2']
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v2"}
		end

		resource :wufoo do
			helpers do
				def authorized
					params['HandshakeKey']==WUFHS
				end

				def add_to_mailing_list(doc)
					merge_fields={}
					merge_fields['FNAME']=doc[:firstName] unless doc[:firstName].nil?
					merge_fields['LNAME']=doc[:lastName] unless doc[:lastName].nil?
					merge_fields['CITY']=doc[:city] unless doc[:city].nil?
					merge_fields['ZIPCODE']=doc[:postalCode] unless doc[:postalCode].nil?
					merge_fields['COUNTRY']=doc[:country] unless doc[:country].nil?
					uri = URI.parse(MCURL)
					http = Net::HTTP.new(uri.host, uri.port)
					http.use_ssl = true
					http.verify_mode = OpenSSL::SSL::VERIFY_NONE
					request = Net::HTTP::Post.new("/3.0/lists/"+MCLIST+"/members/")
					request.basic_auth 'hello',MCKEY
					request.add_field('Content-Type', 'application/json')
					request.body = JSON.dump({
						'email_address'=>doc[:email],
						'status'=>'subscribed',
						'merge_fields'=>merge_fields
					})
					res=http.request(request)
					return res.kind_of?(Net::HTTPSuccess),res
				end
			end

			get do
				# DO NOT DELETE used to test the api is live
				return {"api_version"=>"wufoo/v2"}
			end
		end
	end
end
