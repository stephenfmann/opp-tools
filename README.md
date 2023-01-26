## Fork

Forked to update requirements and packages for modern versions of MYSQL and Python on Ubuntu 22.04.

### Requirements:

**Ubuntu packages**
+ default-libmysqlclient-dev: `sudo apt install default-libmysqlclient-dev`

**Python packages**
+ lxml: `sudo pip install lxml`
+ mysqlclient: `sudo pip install mysqlclient`
+ nltk: `sudo pip install nltk`
+ selenium: `sudo pip install selenium`
+ numpy: `sudo pip install numpy`
+ scikit-learn (aka sklearn): `sudo pip install scikit-learn`
+ googleapiclient: `sudo pip install google-api-python-client`
+ debug: `sudo pip install debug`
+ webdriver-manager: `sudo pip install webdriver-manager`

**Google**
+ Create a google API key https://developers.google.com/custom-search/v1/introduction 
+ Create a custom search engine https://programmablesearchengine.google.com/controlpanel/all
+ Fill in the relevant fields of `config.json`, namely `google_api_key` and `google_cse_id`

**Gecko & Firefox**
+ Install firefox as deb (instead of via snap): follow the instructions here https://www.omgubuntu.co.uk/2022/04/how-to-install-firefox-deb-apt-ubuntu-22-04

**Other**
+ Create folder `log`
+ Change `logfile` in `config.json` so it points to the log folder you just created


## Original
This is a collection of tools to track philosophy papers and blog posts that
recently appeared somewhere on the open internet.





The development of an earlier stage of this software was supported by
the University of London and the UK Joint Information Systems
Committee as part of the PhilPapers 2.0 project (Information
Environment programme).

Copyright (c) 2003-2018 Wolfgang Schwarz, wo@umsu.de

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or (at
your option) any later version. See
http://www.gnu.org/licenses/gpl.html.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

