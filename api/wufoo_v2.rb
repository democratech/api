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
			end

			get do
				# DO NOT DELETE used to test the api is live
				return {"api_version"=>"wufoo/v2"}
			end

			post 'preinscription' do
				error!('401 Unauthorized', 401) unless authorized
				errors=[]
				# 1. We read the new supporter info from the parameters
				doc={}
				doc[:firstName]=params["Field3"].capitalize unless params["Field3"].nil?
				doc[:lastName]=params["Field4"].upcase unless params["Field4"].nil?
				doc[:email]=params["Field12"].downcase unless params["Field12"].nil?
				doc[:zip]=params["Field38"]
				doc[:pays]=params["Field42"].upcase unless params["Field42"].nil?
				doc[:pays]="FRANCE" if doc[:pays].empty?
				doc[:tel]=params["Field11"]
				doc[:programme]=params["Field22"]
				doc[:equipe]=params["Field23"]
				doc[:parti]=(params["Field24"]=="Oui" ? params["Field25"]:params["Field24"])
				doc[:candidat]=(params["Field26"].match(/^Oui/) ? params["Field35"]:params["Field26"]) unless params["Field26"].nil?
				doc[:mandat]=(params["Field34"].match(/^Oui/) ? params["Field36"]:params["Field34"]) unless params["Field34"].nil?
				doc[:siteweb]=params["Field13"]
				doc[:twitter]=params["Field15"]
				doc[:facebook]=params["Field14"]
				doc[:other]=params["Field21"]
				doc[:summary]=params["Field30"]
				doc[:photo_img]=params["Field44"] unless params["Field44"].nil?
				doc[:photo_url]=params["Field44-url"] unless params["Field44"].nil?
				doc[:comment]=params["Field27"]
				attachment=nil
				if doc[:photo_img] then
					attachment={
						"fallback"=>"Photo de %s %s" % [doc[:firstName],doc[:lastName]],
						"color"=>"#527bdd",
						"title"=>doc[:photo_img],
						"title_link"=>doc[:photo_url],
						"image_url"=>doc[:photo_url]
					}
				end
				message=<<END
Nouveau candidat pré-inscrit !
Nom: %s %s
Email: %s / Telephone: %s
Zip: %s (%s)
Type de programme: %s
A une équipe: %s
Adhérent d'un parti: %s
A déjà été candidat: %s
A déjà eu un mandat: %s
Site web: %s
Twitter: %s
Facebook: %s
Autres médias:
%s
Présentation et motivation:
%s
Commentaire libre:
%s
END
				slack_notification(
					message % [
						doc[:firstName],
						doc[:lastName],
						doc[:email],
						doc[:tel],
						doc[:zip],
						doc[:pays],
						doc[:programme],
						doc[:equipe],
						doc[:parti],
						doc[:candidat],
						doc[:mandat],
						doc[:siteweb],
						doc[:twitter],
						doc[:facebook],
						doc[:other],
						doc[:summary],
						doc[:comment]
					],
					"candidats",
					":fr:",
					"wufoo",
					attachment
				)
				if not errors.empty? then
					error!(errors.join("\n"),400)
				end
			end
		end
	end
end
