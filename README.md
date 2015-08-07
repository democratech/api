# democratech API

In order not to require extensive coding resources for coding websites, democratech makes an extensive use of web services, notably:
* Front for shared inbox
* Wufoo for forms
* Slack for communication / notifications
* Bime for analytics
* Mailchimp for emailing
* Zapier for inter-API connections

Nevertheless, we needed a little API of our own in order to properly synchronize all those services.

The API is written in Ruby (not Rails) with the Grape API framework.
The Webserver used is Unicorn (behing nginx).

Make sure you run ```env.sh``` before launching the unicorn server with the following command:
```
bundle exec unicorn -c unicorn.conf.rb
```
