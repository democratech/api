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
				API.log.debug "hash #{hash}\nappId #{appId}\nvoteId #{voteId}"
				if (hash.nil? or appId!=COCORICO_APP_ID) then
					API.log.error "Error : invalid token received :\nAppId #{appId}\nhash #{hash}"
					status 400
					return {"error"=>"invalid token"} 
				end
				if (vote_status!="success" && vote_status!="pending") then
					API.log.error "Error : unknown vote status received :\nStatus [#{vote_status}]\nVoteId #{voteId}\nAppId #{appId}\nhash #{hash}"
					status 400
					return {"msg"=>"vote has not been updated (status:#{vote_status})"}
				end
				begin
					pg_connect()
					update=<<END
UPDATE candidates_ballots AS cb
SET vote_status=$3
FROM (SELECT c.candidate_id,b.ballot_id FROM candidates as c INNER JOIN candidates_ballots as cb ON (cb.candidate_id=c.candidate_id AND c.vote_id=$2) INNER JOIN ballots as b ON (b.ballot_id=cb.ballot_id) INNER JOIN users as u ON (u.hash=$1 AND u.email=b.email)) as z
WHERE cb.candidate_id=z.candidate_id AND cb.ballot_id=z.ballot_id
RETURNING *
END
					res=API.pg.exec_params(update,[hash,voteId,vote_status])
					API.log.warning "Webhook received but no ballot updated #{params}" if res.num_tuples.zero?
				rescue PG::Error => e
					API.log.error "DB Error while updating ballot #{params}\n#{e.message}"
					status 400
					return {"error"=>e.message}
				ensure
					pg_close()
				end
				return { "updated_ballot"=>"ok" }
			end
		end
	end
end
