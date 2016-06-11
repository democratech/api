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
	class AppV1 < Grape::API
		version ['v1','v2']
		format :json

		get do
			# DO NOT DELETE used to test the api is live
			return {"api_version"=>"v1"}
		end

		resource :app do
			get do
				# DO NOT DELETE used to test the api is live
				return {"api_version"=>"app/v1"}
			end

			get 'stats' do
				begin
					pg_connect()
					stats_candidates=<<END
SELECT count(case when c.verified then 1 else null end) as nb_candidates, count(c.candidate_id)-count(case when c.verified then 1 else null end) as nb_citizens
FROM candidates as c;
END
					res1=API.pg.exec(stats_candidates)
					nb_candidates=res1[0]['nb_candidates']
					nb_plebiscites=res1[0]['nb_citizens']
					stats_citizens="SELECT count(*) as nb_citizens from users;"
					res2=API.pg.exec(stats_citizens)
					nb_citizens=res2[0]['nb_citizens']
				rescue Error => e
					return {"error"=>e.message}
				ensure
					pg_close()
				end
				return {
					"nb_citizens"=>nb_citizens,
					"nb_candidates"=>nb_candidates,
					"nb_plebiscites"=>nb_plebiscites,
				}
			end

			get 'maires' do
				begin
					pg_connect()
					stats_maires="SELECT count(*) as nb_signatures FROM appel_aux_maires"
					res1=API.pg.exec(stats_maires)
					nb_signatures=res1[0]['nb_signatures']
				rescue Error => e
					return {"error"=>e.message}
				ensure
					pg_close()
				end
				return {
					"nb_maires"=>0,
					"nb_signatures"=>nb_signatures
				}
			end
		end
	end
end
