# encoding: utf-8

=begin
   Copyright 2016 Telegraph-ai

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
=end

module Democratech
	class Mailer
		@@client=nil

		def initialize
			@@client=Aws::SES::Client.new(credentials: Aws::Credentials.new(AWS_API_KEY,AWS_API_SECRET),region: AWS_REGION_SES)
		end

		def load_template(template)
			path=File.expand_path('../../templates/'+template, __FILE__)
			return nil unless File.exists?(path)
			return File.read(path)
		end

		def send_email(email,template=nil,encoding="UTF-8")
			API.log.info "#{__method__}: email: #{email['to']}"
			begin
				if not template.nil? then
					template_html=API.mailer.load_template(template['name']+".html")
					template_txt=API.mailer.load_template(template['name']+".txt")
					email['html']=template_html unless template_html.nil?
					email['txt']=template_txt unless template_txt.nil?
					template['vars'].each do |k,v|
						email['html'].gsub!(k,v) unless template_html.nil?
						email['txt'].gsub!(k,v) unless template_txt.nil?
					end
				end
				result=@@client.send_email({
					destination: {
						to_addresses: email['to']
					},
					message: {
						body: {
							html: {
								charset: encoding,
								data: email['html']
							},
							text: {
								charset: encoding,
								data: email['txt']
							}
						},
						subject: {
							charset: encoding,
							data: email['subject']
						}
					},
					source: email['from']
				})
			rescue Aws::SES::Errors::ServiceError => e
				msg="A SES error occurred: #{e.class} - #{e.message}"
				API.log.error(msg)
			end
			return result
		end
	end
end
