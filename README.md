## Fork

Forked to update requirements and packages for modern versions of MYSQL and Python on Ubuntu 22.04.

### Requirements:

**Ubuntu packages**
+ default-libmysqlclient-dev: `sudo apt install default-libmysqlclient-dev`

**Firefox & Geckodriver**
+ Make sure both firefox and geckodriver are installed via snap. 
+ `whereis geckodriver` should return `/snap/bin/geckodriver`.

**Document conversion**
+ LibreOffice: 
  + Add LibreOffice Personal Package Archive (PPA): `sudo add-apt-repository ppa:libreoffice/ppa`
  + Update apt: `sudo apt update`
  + Install LibreOffice: `sudo apt install libreoffice`
+ [either unoserver or unoconv: `sudo pip install unoserver` or `sudo apt-get install unoconv`]

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
+ BeautifulSoup4: `sudo pip install beautifulsoup4`

**Perl packages**
+ Text::Capitalize `cpan Text::Capitalize`
+ Text::Aspell `cpan Text::Aspell`
+ Text::Unidecode `cpan Text::Unidecode`
+ Statistics::Lite `cpan Statistics::Lite`
+ Text::Names `cpan Text::Names`
+ JSON `cpan JSON`
+ DBI `cpan DBI`
+ Config::JSON `cpan Config::JSON`
+ String::Approx `cpan String::Approx`
+ Lingua::Stem::Snowball `cpan Lingua::Stem::Snowball`
+ DBD::mysql `cpan DBD::mysql`

**Google**
+ Create a google API key https://developers.google.com/custom-search/v1/introduction 
+ Create a custom search engine https://programmablesearchengine.google.com/controlpanel/all
+ Fill in the relevant fields of `config.json`, namely `google_api_key` and `google_cse_id`

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

