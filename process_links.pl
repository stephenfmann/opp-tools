#! /usr/bin/perl -w
use strict;
use warnings;
use utf8;
use Encode;
use File::Basename qw/dirname/;
binmode STDOUT, ":utf8";
chdir(dirname($0));
use DBI;
use Digest::MD5;
use HTML::LinkExtractor;
use URI;
use Data::Dumper;
use Getopt::Std;
use util::Io;
use util::Errors;
use util::String;
use util::Spamfilter;
use util::Converter;
my %cfg = do 'config.pl';

my %opts;
getopts("v:p:nh", \%opts);
if ($opts{h}) {
    print <<EOF;

Fetches documents and tries to guess author, title, abstract, etc., and
whether they are a paper at all. Run as a cronjob without arguments, or
with arguments for testing and debugging:

Usage: $0 [-hn] [-p url or id] [-v verbosity]

-p        : url or id that will be processed
-v        : verbosity level (0-10)
-n        : dry run, do not write result to DB
-h        : this message

EOF
    exit;
}

my $verbosity = $opts{v} || 0;

# don't run multiple processes in parallel:
if ( -e '.processlock' ) {
    if ( -M '.processlock' < 0.005) {
        # modified in the last ~10 mins
        print "process already running\n" if $verbosity;
        exit;
    }
    print "killing previous run!\n";
    # we are killing ourserlves here!
    system("ps -ef | grep 'l process_links' | grep -v grep"
           ." | awk '{print \$2}' | xargs kill -9"
           ." && rm -f .processlock");
}
system('touch .processlock');

# find some links to check:
my $dbh = DBI->connect('DBI:mysql:'.$cgf{'MYSQL_DB'}, $cfg{'MYSQL_USER'},
    $cfg{'MYSQL_PASS'}, { RaiseError => 1 }) 
    or die "Couldn't connect to database: " . DBI->errstr;
$dbh->{'mysql_auto_reconnect'} = 1;
if ($opts{p}) {
    # from command-line
    my ($url, $id);
    if ($opts{p} =~ /^\d+$/) {
        $id = $opts{p};
 	($url) = $dbh->selectrow_array("SELECT url FROM docs WHERE id = $opts{p}");
	die "ID $opts{p} not in database" unless ($url);
    }
    else {
	$url = $opts{p};
        ($id) = $dbh->selectrow_array("SELECT id FROM docs WHERE url = '$opts{p}'");
    }
    my @links = ({ id => $id, url => $url });
    process_links(@links);
}
else {
    # from database.
    # Do we have unprocessed links?
    my $query = "SELECT id, url FROM docs WHERE status = 0 ORDER BY id LIMIT ".NUM_URLS;
    my @links = @{$dbh->selectall_arrayref($query, { Slice => {} })};
    if (!@links) {
	# No. Toss a coin to decide whether to (a) verify old papers
	# and re-check links with HTTP errors, or (b) give old spam
	# and parser errors a new chance. Mostly we want to do (a).
	# But first, check if we reprocess everything.
	if (REPROCESS_ALL) {
	    $query = "SELECT id, url, filesize, status, "
                ."UNIX_TIMESTAMP(last_checked) AS last_checked FROM docs "
                ."ORDER BY last_checked LIMIT ".NUM_URLS;
	}
	elsif (rand(10) <= 9) {
	    # (a) re-process old papers and HTTP errors:
	    $query = "SELECT id, url, filesize, status, "
                ."UNIX_TIMESTAMP(last_checked) AS last_checked FROM docs "
                ."WHERE (status NOT BETWEEN 2 AND 99) AND NOT is_spam > 0.5 "
                ."ORDER BY last_checked LIMIT ".NUM_URLS;
	}
	else {
	    # (b) give old spam and parser errors a second chance:
	    $query = "SELECT id, url, filesize, is_spam, "
                ."UNIX_TIMESTAMP(last_checked) AS last_checked FROM docs "
                ."WHERE (status = 1 AND is_spam > 0.5) OR status BETWEEN 2 AND 99 "
                ."ORDER BY last_checked LIMIT ".NUM_URLS;
	}
	@links = @{$dbh->selectall_arrayref($query, { Slice => {} })};
    }
    process_links(@links);
}

print "done.\n" if $verbosity;

system('rm -f '.TEMPDIR.'*') unless $verbosity;
system('rm -f .processlock');

$dbh->disconnect() if ($dbh);

# Spam score threshold where we don't bother guessing author etc.:
use constant CERT_SPAM => 0.8;

sub process_links {
    my @links = @_;

    my $really = $opts{n} ? "AND 1 = 0" : "";
    my $db_verify = $dbh->prepare(
        "UPDATE docs SET last_checked = NOW() WHERE id = ? $really");
    my $db_redirect = $dbh->prepare(
        "UPDATE docs SET url = ? WHERE id = ? $really");
    my $db_addsub = $dbh->prepare(
        "INSERT IGNORE into pages (url,parent,author,registered) "
        ."VALUES(?, ?, ?, NOW())");
    my $db_delete = $dbh->prepare(
        "DELETE FROM docs WHERE id = ? $really LIMIT 1");
    my $db_err = $dbh->prepare(
        "UPDATE docs SET status = ?, updated = NOW(), last_checked = NOW() "
        ."WHERE id = ? $really");
    my $db_markdupe = $dbh->prepare(
        "UPDATE docs SET duplicates = ? WHERE id = ? $really");
    my $db_settags = $dbh->prepare(
        "INSERT INTO docs2tags (doc_id, tag_id) VALUES(?, ?)");
    my $db_set = $dbh->prepare(
        "UPDATE docs SET status = ?, filetype = ?, filesize = ?, pages = ?, "
        ."author = ?, title = ?, abstract = ?, is_spam = ?, confidence =?, "
        ."updated = NOW(), last_checked = NOW() WHERE id = ? $really");

    foreach my $link (@links) {
	print "checking link $link->{id}: $link->{url}\n" if $verbosity;

	# retrieve document:
	my $mtime = (defined $link->{last_checked} && !REPROCESS_ALL) ? $link->{last_checked} : 0;
	my $res = fetch_url($link->{url}, $mtime);
	if ($res && $res->code == 304 && defined $link->{last_checked}) {
	    print "not modified.\n" if $verbosity;
	    $db_verify->execute($link->{id}) or print DBI->errstr;
	    next;
	}
	if (!$res || !$res->is_success) {
	    my $status = $res ? $res->code : 900;
	    print "status $status.\n" if $verbosity;
	    if ($status == 404 && defined $link->{status} && $link->{status} == 404) {
		print "link was 404 before; deleting.\n" if $verbosity;
		$db_delete->execute($link->{id}) or print DBI->errstr;
	    }
	    else {
		$db_err->execute($status, $link->{id}) or print DBI->errstr;
	    }
	    # if we have a duplicate, make it the official source:
	    my ($dupe_id) = $dbh->selectrow_array(
                "SELECT id FROM docs WHERE duplicates = $link->{id} ORDER BY status LIMIT 1");
	    if ($dupe_id) {
		$dbh->do("UPDATE docs SET duplicates = NULL WHERE id = $dupe_id $really");
		$dbh->do("UPDATE docs SET duplicates = $dupe_id WHERE duplicates = $link->{id} $really");
	    }
	    next;
	}
	if (!$res->content || !$res->{filesize}) {
	    error("document is empty");
	    $db_err->execute(errorcode(), $link->{id}) or print DBI->errstr;
	    next;
	}
	my $filesize = $res->{filesize};
	my $filetype = $res->{filetype};

	# We want to make sure that we only update an old link if it
	# has really (substantially) changed. HTTP headers are not to
	# be trusted on this. So we also check for changes in
	# filesize:
        my $old_filesize = defined $link->{filesize} ? $link->{filesize} : 0;
	if ($old_filesize && abs($old_filesize-$filesize)/$filesize < 0.2 && !REPROCESS_ALL) {
	    print "no substantial change in filesize; treating as Not Modified.\n" if $verbosity;
	    $db_verify->execute($link->{id}) or print DBI->errstr;
	    next;
	}

	# check if filetype is supported:
	if ($filetype !~ /html|pdf|ps|doc|rtf|txt/) {
	    error("unsupported filetype ".$filetype."\n"); 
	    $db_err->execute(errorcode(), $link->{id}) or print DBI->errstr;
	    next;
	}

	my $content = $res->content;

	# tidy up HTML so that xulrunner doesn't throw errors (for missing frames etc.):
	if ($filetype eq 'html') {
	    $content =~ s/src\s*=\s*[\"\'][^\"\']+[\"\']/src='about:blank'/ig;
	    $content =~ s/src\s*=\s*[^\s>]+/src='about:blank'/ig;
	}

	# save local copy:
	my $file = TEMPDIR.Digest::MD5::md5_hex($link->{url}).'.'.$filetype;
	if (!save($file, $content)) {
	    error("cannot save local file");
	    $db_err->execute(errorcode(), $link->{id}) or print DBI->errstr;
	    next;
	}

	# get some more info from DB:
        my ($cand_title, $source_url, $source_id, $source_parent, $source_au, $cand_author);
        if ($link->{id}) {
            my $query = "SELECT docs.anchortext, pages.url, pages.id, pages.parent, pages.author, authors.name"
                ." FROM docs LEFT JOIN (pages,authors) ON (docs.page = pages.id AND pages.author = authors.id)"
                ." WHERE docs.id = $link->{id}";
            ($cand_title, $source_url, $source_id, $source_parent, $source_au, $cand_author) = 
                $dbh->selectrow_array($query);
            unless (defined $source_id) {
                error("database error: cannot get information about document $link->{id}.");
                $db_err->execute(errorcode(), $link->{id}) or print DBI->errstr;
                next;
            }
        }

	# check if this is a subpage with further links to papers
	# or an intermediate page that leads to the actual paper:
	if ($filetype eq 'html' && $source_id) {
	    my $issub = 1;
	    # subpage must be located at same host and path as parent page:
	    $source_url =~ s/[^\/]+\.[^\/]+$//; # strip filename
	    $issub = $issub && ($link->{url} =~ /^$source_url/);
	    # subpage must have high link density:
	    my $numlinks = 0;
	    $numlinks++ while ($content =~ /<a href/gi);
	    $issub = $issub && $numlinks > 4 && ($numlinks/$filesize > 0.002);
	    # subpage must have at least three links of paper filetypes:
	    $numlinks = 0;
	    $numlinks++ while ($content =~ /\.pdf|\.doc/gi);
	    $issub = $issub && $numlinks > 2;
	    # parent page must not itself be subpage:
	    $issub = $issub && !$source_parent;
	    if ($issub) {
		$db_addsub->execute($link->{url}, $source_id, $source_au) or print DBI->errstr;
		error("looks like a subpage with more links");
		$db_err->execute(errorcode(), $link->{id}) or print DBI->errstr;
		next;
	    }
	    # catch intermediate pages that redirect with meta refresh
	    # (e.g. http://www.princeton.edu/~graff/papers/ucsbhandout.html):
	    my $target = '';
	    if ($content =~ /<meta.*http-equiv.*refresh.*content.*\n*url=([^\'\">]+)/i) {
		print "address redirects to $1.\n" if $verbosity;
		$target = URI->new($1);
		$target = $target->abs(URI->new($link->{url}));
	    }
	    # other intermediate pages are short and have at least one link to a pdf file:
	    elsif ($filesize < 5000
		   && $numlinks > 0
		   && $content =~ /\.pdf/i
		   && $link->{url} !~ m/\.pdf$/i) { # prevent loops with redirects to login?req=foo.pdf
		print "might be a steppingstone page?\n" if $verbosity > 1;
		my $link_extractor = new HTML::LinkExtractor(undef, $res->base, 1);
		eval {
		    $link_extractor->parse(\$res->{content});
		};
		my @as = grep { $$_{tag} eq 'a' && $$_{href} =~ /\.pdf$/ } @{$link_extractor->links};
		print Dumper @as if $verbosity > 1;
		if (@as == 1) { # exactly one pdf link
		    $target = ${$as[0]}{href};
		}
	    }
	    if ($target && length($target) < 256) {
		$target =~ s/\s/%20/g; # fix links with whitespace
		my ($is_dupe) = $dbh->selectrow_array("SELECT 1 FROM docs WHERE url = ".$dbh->quote($target));
		if ($is_dupe) {
		    error("steppingstone to duplicate");
		    $db_err->execute(errorcode(), $link->{id}) or print DBI->errstr;
		}
		else {
		    print "replacing link with $target.\n" if $verbosity;
		    $db_redirect->execute($target, $link->{id}) or print DBI->errstr;
		}
		next;
	    }
	}

	# guess spamminess:
	$link->{anchortext} = $cand_title;
	$link->{filesize} = $filesize;
	$link->{filetype} = $filetype;
	$link->{content} = $content;
        if ($link->{filetype} eq 'html') {
            $link->{text} = strip_tags($content);
        }
	my $is_spam = 0;
	eval {
	    $is_spam = util::Spamfilter::classify($link);
	};
	if ($@) {
	    error($@);
	    $db_err->execute(errorcode(), $link->{id}) or print DBI->errstr;
	    next;
	}
	$is_spam = sprintf("%3f", $is_spam);
	if ($is_spam > 0.5) {
	    if (defined $link->{is_spam}) {
		# was previously recognized as spam as well; don't update 'updated' etc.
		$db_verify->execute($link->{id});
		next;
	    }
	    if ($is_spam >= CERT_SPAM) {
		# certain spam, don't process any further
		$db_set->execute(1, $filetype, $filesize, 0, '', '', '', $is_spam, 0.5, $link->{id});
		next;
	    }
	}

        # convert file to xml:
        my $xml = convert2xml($file);
        print $xml if $self->verbosity > 4;
        save("$file.xml", $xml, 1);

	# extract author, title, abstract:
	$cand_title = '' if ($cand_title && ($cand_title !~ /\w\w/ || $cand_title =~ /$filetype|version/i));
	my $result;
	eval {

xxx call meta here

	    my $extractor = metaparser::Extractor->new($file);
	    $extractor->verbosity($verbosity);
	    $extractor->prior('author', $cand_author, 0.7) if ($cand_author);
	    $extractor->prior('title', $cand_title, 0.5) if ($cand_title);
	    $result = $extractor->parse();
	};
	if ($@) {
	    error("$@");
	    error("parser error") if errorcode() == 99;
	    $db_err->execute(errorcode(), $link->{id}) or print DBI->errstr;
	    next;
	}

	my $author = join ', ', @{$result->{authors}};
	my $title = $result->{title};
	my $abstract = $result->{abstract};
	my $confidence = $result->{confidence};
	my $pages = $result->{pages};
        my $text = $result->{text};

	# when parsing PDFs, we sometimes get mess that is not valid UTF-8, which can
	# make the HTML/RSS invalid. Discard such entries:
	unless (Encode::is_utf8("$author $title $abstract",1)) {
	    $author = decode 'utf8', $author;
	    $title = decode 'utf8', $title;
	    $abstract = decode 'utf8', $abstract;
	    unless (Encode::is_utf8("$author $title $abstract",1)) {
		error("non-UTF8 characters in metadata: $author, $title, $abstract");
		$db_err->execute(errorcode(), $link->{id});
		next;
	    }
	}

	# guess spamminess again, now that we definitely have the text content:
        $link->{text} = $text;
	my $is_spam = 0;
	util::Spamfilter::verbosity($verbosity);
        eval {
	    $is_spam = util::Spamfilter::classify($link);
	};
	if ($@) {
	    error($@);
	    $db_err->execute(errorcode(), $link->{id}) or print DBI->errstr;
	    next;
	}
	$is_spam = sprintf("%3f", $is_spam);
	if ($is_spam > 0.5 && defined $link->{is_spam}) {
            # was previously recognized as spam as well; don't update 'updated' etc.
            $db_verify->execute($link->{id});
            next;
	}

	# check for duplicates (uses the MySQL levenshtein UDF from joshdrew.com)
	my $query = "SELECT id,filetype FROM docs WHERE status = 1 AND id != $link->{id} AND duplicates IS NULL"
                ." AND levenshtein(author,".$dbh->quote($author).") < 4"
	        ." AND levenshtein(title,".$dbh->quote($title).") < 4"
	        ." AND levenshtein(abstract,".$dbh->quote($abstract).") < 15"
                ." LIMIT 1";
	my ($orig_id, $orig_filetype) = $dbh->selectrow_array($query);
	if ($orig_id) {
	    print "duplicate of $orig_id.\n" if $verbosity;
	    my $dupe_id = $link->{id};
	    if ($filetype eq 'pdf' && $orig_filetype ne 'pdf') {
		# set other version as duplicate of this one:
		$dupe_id = $orig_id;
		$orig_id = $link->{id};
	    }
	    $db_markdupe->execute($orig_id, $dupe_id);
	}

	# xxx missing: classify the document again, by topic. For now
	# we simply let the document inherit the first tag from the source
	# page author (this is for filtering out _pp stuff):
	my @tag_ids = @{$dbh->selectcol_arrayref("\
           SELECT tag_id FROM authors2tags WHERE author_id = $source_au
        ")};
	if (@tag_ids) {
	    $dbh->do("INSERT IGNORE INTO docs2tags (doc_id, tag_id) VALUES ($link->{id}, $tag_ids[0])");
	    print "$title has tag $tag_ids[0].\n";
	}

	# xxx missing: recognize if something is a book chapter, a
	# review, etc. and handle it appropriately.

	$db_set->execute(1, $filetype, $filesize, $pages, $author, $title, $abstract, $is_spam, $confidence, $link->{id})
	    or print DBI->errstr;
	print "RESULT: $filetype, $filesize, $pages, $author, $title, $abstract, $is_spam, $confidence.\n\n" if $verbosity;
    }
}
