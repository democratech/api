# encoding: utf-8

module Democratech
	class V2 < Grape::API
		prefix 'api'
		version 'v2'
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v2"}
		end
	end
end
