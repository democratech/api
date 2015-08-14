![democratech logo](http://democratech.co/static/logo-dark-trbg-260x40.png)
# Services API

## Context

In order not to require extensive coding resources for coding websites, democratech makes an extensive use of web services behind the scene, most notably:
* [Bime](https://bimeanalytics.com) for analytics and dashboards
* [Front](http://frontapp.com) for shared inbox
* [Wufoo](https://wufoo.com) for forms
* [Slack](https://slack.com) for communication / notifications
* [Mailchimp](https://mailchimp.com) for emailing

Nevertheless, we needed an API of ours (Zapier-like) to properly synchronize all those services.

## Process overview

The services API is located on the green "Supporteurs" node.
### Citizen signing process
![Citizen subscription process](http://democratech.co/static/citizen_signing_process.png)

### Citizen contributing process
![Citizen contributing process](http://democratech.co/static/citizen_contributing_process.png)

## About the Services API

The Services API is written in Ruby and leverages the [Grape API framework](https://github.com/ruby-grape/grape).
The Webserver used is [Unicorn](http://unicorn.bogomips.org/) (behing nginx).

## Installing and starting the Services API

1. Make sure your run ```bundle install``` to make sure all dependencies get installed
2. Create a ```config/keys.local.rb``` file with all the necessary information (cf ```config/keys.rb```)
3. launch the unicorn server with the following command:
```
bundle exec unicorn -c config/unicorn.conf.rb config/config.ru
```

Alternatively for development purposes, you can also just run the Services API with rackup to use the default WEBRick web server:
```
rackup config/config.ru
```

## Accessing the Services API

You can test that the Services API is up and running by calling:
```
curl http://127.0.0.1:9292/api/v1/test
```
It should return an HTTP 200 OK

## Contributing

1. [Fork it](http://github.com/democratech/api/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Authors

So far, democratech's Services API is being developed and maintained by
* [Thibauld Favre](https://twitter.com/thibauld)
* [Jean-Tristan Chanègue](https://www.linkedin.com/in/jeantristanchanegue)
* Feel free to join us! 

## License

* democratech Services API is released under the [GNU Affero GPL](https://github.com/democratech/website/blob/master/LICENSE)
* Grape is released under a [Free Software license](https://github.com/ruby-grape/grape/blob/master/LICENSE).

