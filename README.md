# democratech API

In order not to require extensive coding resources for coding websites, democratech makes an extensive use of web services behind the scene, most notably:
* [Bime](https://bimeanalytics.com) for analytics and dashboards
* [Front](http://frontapp.com) for shared inbox
* [Wufoo](https://wufoo.com) for forms
* [Slack](https://slack.com) for communication / notifications
* [Mailchimp](https://mailchimp.com) for emailing
* [Zapier](https://zapier.com) for inter-API connections

Nevertheless, we needed a little API of our own in order to properly synchronize all those services.

The API is written in Ruby and leverages the [Grape API framework](https://github.com/ruby-grape/grape).
The Webserver used is [Unicorn](http://unicorn.bogomips.org/) (behing nginx).

Make sure you create a ```config/keys.local.rb``` file with all the necessary information (cf ```config/keys.rb```) and then launch the unicorn server with the following command:
```
bundle exec unicorn -c config/unicorn.conf.rb config/config.ru
```

Alternatively for development purposes, you can also just run the API with:
```
rackup config/config.ru
```
This will use the default WEBRick web server.
