package Data::Format::CSV;
use strict;
our $VERSION = 0.1;

use Exporter qw(import);
use Perl::Module;
use Data::Hub::Util qw(fs_handle);
use Data::Hub::Container qw(curry);

our @EXPORT = qw();
our @EXPORT_OK = qw(
  csv_parse
);
our %EXPORT_TAGS = (all => [@EXPORT_OK],);

# ------------------------------------------------------------------------------
# CSV Parsing Conventions
#
#   Byte-order mark is 65279, and will be stripped
#   Headers are in the first row
#   Embedded delimters, field need to be enclosed in quotes
#   Embedded quotes, need to be doubled up
#
# ------------------------------------------------------------------------------

sub csv_parse {
  my $rows = [];
  my $parser = __PACKAGE__->new(@_, rows => $rows);
  while ($parser->has_next) {
    push @$rows, curry($parser->next);
  }
  return $parser;
}

# ------------------------------------------------------------------------------
# new - Data::Format::CSV
#
# Data::Format::CSV->new(path => 'export.csv');
# Data::Format::CSV->new(path => 'export.tsv', delimiter => "\t");
#
# When the first line of the CSV indicates the delimiter, such as
# 
#   SEP=,
#
# We will update accordingly, regardless of what was specified in the constructor.
# See also: https://superuser.com/questions/773644/what-is-the-sep-metadata-you-can-add-to-csvs
# ------------------------------------------------------------------------------

sub new () {
  my $pkg = ref($_[0]) ? ref(shift) : shift;
  my $self = bless {
    'binmode' => ':encoding(UTF-8)',
    'delimiter' => ',',
    'columns' => [],
    'rows' => [],
    'fh' => undef,
    @_
  }, $pkg;
  if (-e $$self{'path'}) {
    $$self{'fh'} = fs_handle($$self{'path'}, 'r') or croak "$!: $$self{'path'}";
    binmode $$self{'fh'}, $$self{'binmode'};
    $self->parse_header();
  } else {
    warnf ("Path does not exist: %s", $$self{'path'}) if $$self{'path'};
  }
  return $self;
}

# ------------------------------------------------------------------------------
# parse_header - 
# ------------------------------------------------------------------------------

sub parse_header() {
  my $self = shift;
  my @chars = split //, $$self{'fh'}->getline;
  shift @chars if ord($chars[0]) == 65279; # BOM
  my $line = join '', @chars;
  if ($line =~ /^(?:sep|SEP)=(.)/) {
    $$self{'delimiter'}=$1;
    $line = $$self{'fh'}->getline;
  }
  $line =~ s/[\r\n]+$//;
  my $columns = $self->_split($line);
  #TODO:provide normalize_column_name callback if such is needed
  #$columns = [map {s/\s/_/g;$_} @$columns];
  $$self{'columns'} = $columns;
}

# ------------------------------------------------------------------------------
# has_next - 
# ------------------------------------------------------------------------------

sub has_next() {
  my $self = shift;
  return $$self{'fh'} ? !$$self{'fh'}->opened || !$$self{'fh'}->eof : 0;
}

# ------------------------------------------------------------------------------
# next - 
# ------------------------------------------------------------------------------

sub next() {
  my $self = shift;
  my $fields = $self->_next;
  my $result = Data::OrderedHash->new();
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
  $$self{'fh'}->eof and delete $$self{'fh'};
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
  foreach my $fragment (split $$self{'delimiter'}, $_[0]) {
    if ($accumulating && $fragment =~ s/^"$//) {
      $accumulating = 0;
    }
    if ($fragment =~ s/^"(?!")//) {
      $accumulating = 1;
    }
    if ($fragment =~ s/(?<!")"{1}$//) {
      $accumulating = 0;
    }
    if (!$accumulating && $fragment =~ s/^""$//) {
      $fragment = '';
    }
    push @field, $fragment;
    if (!$accumulating) {
      my $value = join($$self{'delimiter'}, @field);
      $value =~ s/^\s+//;
      $value =~ s/\s+$//;
      $value =~ s/""/"/g;
      $value = undef if defined $value && $value eq 'NULL';
      push @$result, $value;
      @field = ();
    }
  }
  return $result;
}

1;

__END__

# ------------------------------------------------------------------------------
# _escape - Escape embedded quotes and quote entire field
# ------------------------------------------------------------------------------

sub _escape {
  my $self = shift;
  my $value = shift;
  return $value if is_numeric($value);
  $value =~ s/"/\\"/g;
  return sprintf('"%s"', $value);
}

sub _write_row {
  my $self = shift;
  my $fh = $self->{'fh'};
  my $row = sprintf join ',', map { $self->_escape($_) } @_;
  printf $fh "%s\n", $row;
  return $row;
}
