package Data::Format::CSV;
use strict;
our $VERSION = 0.1;

use Exporter;
use Perl::Module;
use Data::Hub::Util qw(fs_handle);

our @EXPORT = qw();
our @EXPORT_OK = qw(
  csv_parse
);
our %EXPORT_TAGS = (all => [@EXPORT_OK],);

sub csv_parse {
  my $result = [];
  my $parser = Data::Format::CSV->new(@_, rows => $result);
  while ($parser->has_next) {
    push @$result, $parser->next;
  }
  return $parser;
}

# ------------------------------------------------------------------------------
# new - Local::Parse::CSV
#
# Local::Parse::CSV->new('export.csv');
# Local::Parse::CSV->new('export.tsv', delimiter => "\t");
# ------------------------------------------------------------------------------

sub new () {
  my $pkg = ref($_[0]) ? ref(shift) : shift;
  my $path = shift or die "Please provide a file path";
  my $self = bless {
    'path' => $path,
    'binmode' => ':encoding(UTF-8)',
    'delimeter' => ',',
    'columns' => [],
    'fh' => undef,
    @_
  }, $pkg;
  if (-e $$self{'path'}) {
    $$self{'fh'} = fs_handle($$self{'path'}, 'r') or croak "$!: $$self{'path'}";
    binmode $$self{'fh'}, $$self{'binmode'};
    $self->parse_header();
  }
  return $self;
}

# ------------------------------------------------------------------------------
# parse_header - 
# ------------------------------------------------------------------------------

sub parse_header() {
  my $self = shift;
  $$self{'columns'} = $self->_next;
}

# ------------------------------------------------------------------------------
# has_next - 
# ------------------------------------------------------------------------------

sub has_next() {
  my $self = shift;
  return !$$self{'fh'}->opened || !$$self{'fh'}->eof;
}

# ------------------------------------------------------------------------------
# next - 
# ------------------------------------------------------------------------------

sub next() {
  my $self = shift;
  my $fields = $self->_next;
  my $result = {};
  for (my $i = 0; $i < @{$$self{'columns'}}; $i++) {
    $result->{$$self{'columns'}[$i]} = $$fields[$i];
  }
  return $result;
}

# ------------------------------------------------------------------------------
# _next - 
# ------------------------------------------------------------------------------

sub _next () {
  my $self = shift;
  my $line = $$self{'fh'}->getline;
  $line =~ s/[\r\n]+$//;
  return $self->_split($line);
}

# ------------------------------------------------------------------------------
# _split - 
# ------------------------------------------------------------------------------

sub _split() {
  my $self = shift;
  my $result = [];
  my @field = ();
  my $accumulating = 0;
  foreach my $fragment (split ',', $_[0]) {
    if ($fragment =~ s/^\"//) {
      $accumulating = 1;
    }
    if ($fragment =~ s/\"$//) {
      $accumulating = 0;
    }
    push @field, $fragment;
    if (!$accumulating) {
      my $value = join(',', @field);
      $value =~ s/^\s+//;
      $value =~ s/\s+$//;
      $value = undef if defined $value && $value eq 'NULL';
      push @$result, $value;
      @field = ();
    }
  }
  return $result;
}

1;
