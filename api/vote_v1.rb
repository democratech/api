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
	class VoteV1 < Grape::API
		version ['v1']
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v1"}
		end

		resource :vote do
			helpers do
				def authorized(token)
					#decoded_token= JWT.decode token, SIGNIN_SECRET, true, {:algorithm => 'HS256'}
					return true
				end
			end

			get do
				# DO NOT DELETE used to test the api is live
				return {"api_version"=>"vote/v1"}
			end

			get 'casted' do
				API.log.warn "Vote casted (GET) #{params}"
				return params
			end

			post 'casted' do
				appId,hash=params['event']['user']['sub'].split(':')
				vote_status=params['event']['status']
				voteId=params['event']['vote']['id']
				statuses=["error","pending","success"]
				API.log.debug "hash #{hash}\nappId #{appId}\nvoteId #{voteId}"
				if (hash.nil? or appId!=COCORICO_APP_ID) then
					API.log.error "Error : invalid token received :\nAppId #{appId}\nhash #{hash}"
					return {"error"=>"invalid token"} 
				end
				if !statuses.include?(vote_status) then
					API.log.error "Error : unknown vote status received :\nStatus [#{vote_status}]\nVoteId #{voteId}\nAppId #{appId}\nhash #{hash}"
					return {"msg"=>"vote has not been updated (status:#{vote_status})"}
				end
				begin
					pg_connect()
					update=<<END
UPDATE ballots AS b SET vote_status=$3, date_notified=now()
FROM (SELECT v.vote_id,u.email FROM users as u INNER JOIN ballots as b ON (b.email=u.email AND u.hash=$1) INNER JOIN votes as v ON (v.vote_id=b.vote_id AND v.cc_vote_id=$2)) as z
WHERE b.vote_id=z.vote_id AND b.email=z.email
RETURNING *
END
					res=API.pg.exec_params(update,[hash,voteId,vote_status])
					API.log.error "Webhook received but no ballot updated #{params}" if res.num_tuples.zero?
				rescue PG::Error => e
					API.log.error "DB Error while updating ballot #{params}\n#{e.message}"
					return {"error"=>e.message}
				ensure
					pg_close()
				end
				return { "updated_ballot"=>"ok" }
			end
		end
	end
end
