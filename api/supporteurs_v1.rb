# encoding: utf-8

module Democratech
	class SupporteursV1 < Grape::API
		prefix 'api'
		version ['v1','v2']
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v1"}
		end

		resource :supporteurs do

			get do
				# DO NOT DELETE used to test the api is live
				return {"api_version"=>"supporteurs/v1"}
			end

			get 'total' do
				nb_supporteurs=API.db[:supporteurs].find().count
				return {"nb_supporteurs"=>nb_supporteurs}
			end
		end
	end
end
