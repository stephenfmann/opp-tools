package Converter;
use strict;
use utf8;
use Encode;
use Data::Dumper;
use Exporter;
use util::Sysexec;
use util::String;
use util::Io;
binmode STDOUT, ":utf8";
our @ISA = ('Exporter');
our @EXPORT = qw(&convert2text &convert2pdf &convert2xml &converters);

my $verbosity = 0;
sub verbosity {
   $verbosity = shift if @_;
   return $verbosity;
}

my %cfg;
sub cfg {
   %cfg = shift if @_;
   return %cfg;
}

my @converters_used;
sub converters {
   return join ' ',@converters_used;
}

sub convert2pdf {
    my $source = shift or die "convert2pdf requires source filename parameter";
    my $target = shift or die "convert2pdf requires target filename parameter";
    my ($basename, $filetype) = ($source =~ /^(.*?)\.?([^\.]+)$/);
    print "converting $source to pdf\n" if $verbosity;
  SWITCH: for ($filetype) {
      /doc/ && do {
	  push @converters_used, 'antiword';
	  my $command = $cfg{'ANTIWORD'}
	      .' -aa4'      # output as PDF in a4 format
	      .' -i1'       # ignore images
	      .' -m 8859-1' # character encoding: antiword doesn't support utf8
	      ." $source"   # source file
	      .' 2>&1';     # stderr to stdout
	  print "$command\n" if $verbosity >= 2;
	  my $content = sysexec($command, 10, $verbosity) || '';
	  $content = Encode::decode('iso-8859-1', $content) || $content;
	  die "antiword failed: $content" unless ($content && $content =~ /%PDF/);
	  return save($target, $content);
      };
      /rtf/ && do {
	  push @converters_used, 'rtf2pdf';
	  my $command = $cfg{'RTF2PDF'}
	      ." $source"     # source file
	      ." $target"     # destination file
	      .' 2>&1';       # stderr to stdout
	  print "$command\n" if $verbosity >= 2;
	  my $out = sysexec($command, 10, $verbosity);
	  print $out if $verbosity >= 4;
	  die "rtf2pdf failed: $out" unless -e $target;
	  return 1;
      };
      /ps/ && do {
	  push @converters_used, 'ps2pdf';
	  my $command = $cfg{'PS2PDF'}
	      ." $source"     # source file
	      ." $target"     # destination file
	      .' 2>&1';       # stderr to stdout
	  print "$command\n" if $verbosity >= 2;
	  my $out = sysexec($command, 10, $verbosity) || '';
	  print $out if $verbosity >= 4;
	  die "ps2pdf failed: $out" unless -e $target;
	  return 1;
      };
      die "$source has unsupported filetype";
  }
}

sub convert2text {
    my $filename = shift or die "convert2text requires filename parameter";
    my ($basename, $filetype) = ($filename =~ /^(.*?)\.?([^\.]+)$/);
    my $text;
    print "getting plain text from $filename\n" if $verbosity;
    if (!(-e $filename)) {
	die "$filename does not exist";
    }
  SWITCH: for ($filetype) {
      /html/ && do {
	  # strip tags:
	  $text = readfile($filename);
          $text = strip_tags($text);
	  last;
      };
      /pdf/ && do {
	  my $command = $cfg{'RPDF'}
	      ." $filename"
	      .' 2>&1';
	  print "$command\n" if $verbosity >= 3;
	  my $xml = sysexec($command, 60, $verbosity) || '';
          $text = strip_tags($xml);
	  last;
      };
      /doc|rtf|ps/ && do {
	  # xxx hack: works, but inefficient:
	  convert2pdf($filename, "$filename.pdf") or return undef;
	  $text = convert2text("$filename.pdf");
	  last;
      };
      /txt/ && do {
	  $text = readfile($filename);
	  last;
      };
      die "convert2text: unsupported filetype ($filetype): $filename";
  }
    print "$text\n" if $verbosity >= 4;
    return $text;
}


sub convert2xml {
    my $filename = shift or die "convert2text requires filename parameter";
    my ($basename, $filetype) = ($filename =~ /^(.*?)\.?([^\.]+)$/);
    print "getting XML from $filename\n" if $verbosity;
  SWITCH: for ($filetype) {
      /pdf/ && do {
	  my $command = $cfg{'RPDF'}
	      ." $filename"
	      .' 2>&1';
	  print "$command\n" if $verbosity >= 3;
	  my $xml = sysexec($command, 60, $verbosity) || '';
	  return $xml;
      };
      /html|txt/ && do {
	  my $command = $cfg{'RHTML'}
	      ." $filename"
	      .' 2>&1';
	  print "$command\n" if $verbosity >= 3;
	  my $xml = sysexec($command, 60, $verbosity) || '';
	  return $xml;
      };
      # convert other formats to PDF:
      if (convert2pdf($filename, "$filename.pdf")) {
	  return convert2xml("$filename.pdf", );
      }
      die "PDF conversion failed";
  }
}

1;

