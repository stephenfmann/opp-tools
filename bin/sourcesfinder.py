#!/usr/bin/env python3
import argparse
import logging
import os, sys, time
from pathlib import Path
import re
import hashlib
from random import randint
import findmodules
from opp import db, util, googlesearch
from opp.models import Source
from opp.debug import debug, debuglevel
import json
import urllib

'''
This script is supposed to be run from the command line (or regularly
as a cron job) to find new source pages.
'''

LOCKFILE = '/tmp/sourcesfinder_wait.lk'
GOOGLE_REST_TIME = 60*60*9 # wait 9 hours if google locked us out

class SourcesFinder:

    def __init__(self):
        pass
    
    def select_names(self, num_names):
        """return list of num names names from db to check for new papers pages"""
        cur = db.cursor()
        query = "SELECT name FROM author_names WHERE is_name=1 ORDER BY last_searched ASC LIMIT {}".format(num_names)
        cur.execute(query)
        rows = cur.fetchall()
        return [row[0] for row in rows]

    def update_author(self, name):
        """update last_searched field for author <name>"""
        cur = db.cursor()
        query = "UPDATE author_names SET last_searched=NOW() WHERE name=%s"
        cur.execute(query, (name,))
        db.commit()

    def find_new_pages(self, name, store_in_db=True):
        """
        searches for Source pages matching author name and adds them to
        the sources db
        """
        debug(1, "\nsearching source pages for %s", name)
        stored_publications = Source.get_stored_publications(name)
        pages = set()
        search_terms = ['"{}"'.format(name)]
        # We vary the query to hide we're a bot and give us better
        # chances of finding a source page after several tries.
        if len(stored_publications) > 1 and randint(0,1) == 0:
            for title in stored_publications[:2]:
                title3words = ' '.join(title.split()[:3])
                search_terms.append('"{}"'.format(title3words))
        else:
            search_terms.append('~philosophy')
            more_terms = [
                '(publications OR articles OR papers OR "in progress" OR forthcoming)',
                '(publications OR articles OR forthcoming)',
                '(publications OR articles OR "in progress" OR forthcoming)'
            ]
            search_terms.append(more_terms[randint(0,2)])
        random_more_terms = [
            # careful: -site:google.com blocks sites.google.com...
            '-filetype:pdf',
            '-site:philpapers.org',
            '-site:wikipedia.org',
            '-site:academia.edu',
        ]
        for term in random_more_terms:
            if randint(0,2) != 0:
                search_terms.append(term)
        search_phrase = ' '.join(search_terms)
        debug(2, search_phrase)
        # vary interval between searches to hide that we're a bot:
        sleeptime = randint(0,100)
        debug(2, "waiting for %s seconds", sleeptime)
        time.sleep(sleeptime)
        try:
            searchresults = googlesearch.search(search_phrase)
        except Exception as e:
            debug(1, "Ooops. Looks like google caught us. Creating lock file to enforce break.")
            Path(LOCKFILE).touch()
            raise
            
        # search full name first, then last name only:
        #searchresults = set(googlesearch.search(search_phrase))
        #search_phrase = '"{}" '.format(name.split()[-1]) + ' '.join(search_terms)
        #searchresults |= set(googlesearch.search(search_phrase))
        for url in searchresults:
            debug(1, '\n'+url)
            url = util.normalize_url(url)
            if self.bad_url(url):
                debug(1, "bad url")
                continue
            # check if url is already known:
            cur = db.cursor()
            cur.execute("SELECT 1 FROM sources WHERE url = %s", (url,))
            rows = cur.fetchall()
            if rows:
                debug(1, "url already known")
                continue
            try:
                status, r = util.request_url(url)
                if status != 200:
                    raise Exception('status {}'.format(status))
            except Exception as e:
                debug(1, "cannot retrieve url %s (%s)", url, e)
                continue
            source = Source(
                url=url,
                default_author=name,
                name="{}'s site".format(name),
                html=r.text
            )
            source.compute_p_is_source(stored_publications=stored_publications)
            if source.is_source < 75:
                debug(1, "doesn't look like a papers page")
                continue
            for dupe in source.get_duplicates():
                # Now what? Sometimes the present URL is the
                # correct new URL to use (e.g., everything is
                # moving to 'https'). Other times the variants are
                # equally valid. In neither case does it probably
                # hurt to overwrite the old URL.
                debug(1, "duplicate of already known %s", dupe.url)
                debug(1, "changing url of source %s to %s", dupe.source_id, url)
                dupe.update_db(url=url)
                break
            else:
                debug(1, "new papers page!")                
                source.save_to_db()
        self.update_author(name)

    def bad_url(self, url):
        """returns True if url is too long or contains blacklisted part"""
        if len(url) > 255:
            return True
        if url.endswith('.pdf'):
            return True
        url = url.lower()
        return any(w in url for w in self.BAD_URL_PARTS)

    BAD_URL_PARTS = [
        'academia.edu',
        'jstor.org', 'springer.com', 'wiley.com', 'journals.org',
        'tandfonline.com', 'ssrn.com', 'oup.com', 'mitpress.mit.edu',
        'plato.stanford.edu', 'scribd.com', 'archive.org',
        'philsci-archive.pitt',
        'umich.edu/e/ergo', 'cambridge.org', 'hugendubel.',
        'dblp.uni-trier', 'dblp.org', 'citec.repec.org', 'publicationslist.org',
        'philarchive.org', 'aristoteliansociety.org.uk/the-proceedings',
        'semanticscholar.org', 'oalib.com', 'academia-net',
        '/portal/en/',  # PURE
        'wikipedia.', 'wikivisually.', 'wikivividly.',
        'researchgate.net', 'scholar.google', 'books.google', 'philpapers.',
        'philx.org', 'philpeople.',
        'ratemyprofessors.', 
        'amazon.', 'twitter.', 'goodreads.', 'pinterest.com', 'ebay.',
        'dailynous.com', 'ipfs.io/', 'philostv.com', 'opp.weatherson',
        'typepad.com/blog/20', 'm-phi.blogspot.de',
        'blogspot.com/20', 'whatisitliketobeaphilosopher.com',
        'workshop', 'colloquium',
        'courses', '/teaching', 'conference', '/news/', '/events/', '/event/',
        '/call', '/search', '/lookup',
    ]

    def sendmail(self, new_pages):
        body = ''
        for (name, url) in new_pages:
            body += "new source page {} for {}\n".format(url,name)
            body += "Edit: http://umsu.de/opp/edit-source?url={}\n\n".format(url)
        #msg = MIMEText(body, 'plain', 'utf-8')
        #msg['Subject'] = '[new source pages]'
        #msg['From'] = 'Philosophical Progress <opp@umsu.de>'
        #msg['To'] = 'wo@umsu.de'
        #s = smtplib.SMTP('localhost')
        #s.sendmail(msg['From'], [msg['To']], msg.as_string())
        #s.quit()

    def test(self):
        tests = {
            # easy cases:
            'Wolfgang Schwarz': { 'http://www.umsu.de/papers/' },
            'Bryan Pickel': { 'https://sites.google.com/site/bryanpickel/Home/re' },
            'Brian Rabern': { 'https://sites.google.com/site/brianrabern/' },
            # no separate papers page:
            'Ted Sider': { 'http://tedsider.org' },
            'Michael Smith': { 'http://www.princeton.edu/~msmith/' },
            'Aaron James': { 'http://www.faculty.uci.edu/profile.cfm?faculty_id=4884' },
            # paper links on many pages:
            'Brian Weatherson': { 'http://brian.weatherson.org/papers.html' },
            # author name not on papers page:
            'Aaron J Cotnoir': { 'http://www.st-andrews.ac.uk/~ac117/writing.html' },
            'Adam Morton': { 'http://www.fernieroad.ca/a/PAPERS/papers.html' }, 
        }
        sf = SourcesFinder()
        for name, sites in tests.items():
            print("\n\ntesting {}".format(name))
            urls = sf.find_new_pages(name, store_in_db=False)
            if urls == sites:
                print("   OK")
            else:
                print("   expected: {}, got: {}".format(sites, urls))


if __name__ == "__main__":

    ap = argparse.ArgumentParser()
    ap.add_argument('-v', '--verbose', action='store_true', help='turn on debugging output')
    ap.add_argument('-n', '--name', type=str, help='search source pages for given author name')
    ap.add_argument('-d', '--dry', action='store_true', help='do not store pages in db')
    args = ap.parse_args()

    loglevel = logging.DEBUG if args.verbose else logging.INFO
    logger = logging.getLogger('opp')
    ch = logging.StreamHandler(sys.stdout)
    ch.setLevel(loglevel)
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logger.addHandler(ch)
    logger.setLevel(loglevel)
    debuglevel(4 if args.verbose else 1)

    if os.path.exists(LOCKFILE):
        if os.path.getctime(LOCKFILE) > time.time()-GOOGLE_REST_TIME:
            debug(1, "google locked us out; waiting.")
            sys.exit(0)
        else:
            os.remove(LOCKFILE)
    
    sf = SourcesFinder()
    if args.name:
        names = [args.name]
    else:
        names = sf.select_names(num_names=1)
    for name in names:
        pages = sf.find_new_pages(name, store_in_db=(not args.dry))
     
    sys.exit(0)
