package Perl::ModuleInfo;
use strict;

use Perl::Module;
use Perl::Util qw(:all);
use Perl::Class;
use Error::Programatic;
use Error::Logical;
use Data::Hub::Util qw(:all);
use Data::Hub::Container;
use Data::Hub::FileSystem::File;

use base qw(Perl::Class::Hash Data::Hub::Container);

our $VERSION = 1.3;

our $TESTS = 'true|false|defined|abort|match|regex';
our $PODHANDLERS = 'summary|synopsis|description|seealso|sub';
our $BASEPACKAGES = 'strict|warnings|UNIVERSAL|base';

sub new {
  my $class = ref($_[0]) ? ref(shift) : shift;
  my $self = $class->SUPER::new();
  $self->{tests} = [];
  $self->{docs} = [];
  $self;
}

sub _append_line (\$$) {
  my $base_text = shift;
  my $text = shift;
  # If this line is indented, and an empty newline preceded this line,
  # then give that empty newline a two-space indentation so that these
  # CODE blocks (in the rendered pod2html HTML) are contiguous.
  if ($text =~ /^ {2,}/ && $$base_text =~ s/^( +[^\n]+)\n\Z\n/$1\n  \n/m) {
    $$base_text =~ s/\n\z/  \n/s;
  }
  $$base_text .= $text . "\n";
}

sub parse {
  my $self = shift;
  throw Error::NotStatic unless isa($self, __PACKAGE__);
  my $lib_path = shift;
  my $mod_path = shift;
  my $path = path_normalize("$lib_path/$mod_path");
  my $module = Data::Hub::FileSystem::File->new($path);
  my $have_used = 0;
  my $tests = $self->{tests};
  my $docs = $self->{docs};
  my $pkg = undef;
  my $method = undef;
  my ($t,$lineno,$slurp,$into) = ('','',0,'','');
  for (split $/, $module->to_string) {
    $lineno++;

    # Begin new package
    m/^package\s*(.*);/ and do {
      $pkg = {
        'path'          => $path,
        'name'          => $1,
        'summary'       => '',
        'synopsis'      => '',
        'description'   => '',
        'seealso'       => '',
        'version'       => [0, 0, 0],
        'export'        => '',
        'export_ok'     => '',
        'export_tags'   => {},
        'depends'       => {},
        'methods'       => {
          'private'     => [],
          'public'      => [],
        },
        'tests'         => [],
      };
      unless ($have_used) {
        eval {require $path} unless $INC{$mod_path};
        $have_used = 1;
      }
      no strict 'refs';
      my @exp = @{"$$pkg{name}\::EXPORT"};
      @exp and $pkg->{export} = join ', ', @exp;
      my @exp_ok = @{"$$pkg{name}\::EXPORT_OK"};
      @exp_ok and $pkg->{export_ok} = join ', ', @exp_ok;
      my %exp_tags = %{"$$pkg{name}\::EXPORT_TAGS"};
      if (%exp_tags) {
        foreach my $tag (keys %exp_tags) {
          $pkg->{export_tags}->{$tag} = join ', ', @{$exp_tags{$tag}};
        }
      }
      if (my $ver = ${"$$pkg{name}\::VERSION"}) {
        my @version = split(/\./, $ver);
        $pkg->{version}[0] = $version[0] || 0;
        $pkg->{version}[1] = $version[1] || 0;
        $pkg->{version}[2] = $version[2] || 0;
      }
      push @$docs, $pkg;
      next;
    };

    # Module dependencies
    m/^use\s+([^\s;]+)/ and do {
      my $dep = $1;
      unless ($dep =~ /^($BASEPACKAGES)$/) {
        $pkg->{depends}{$dep} = 0;
      }
      next;
    };

    # Custom POD handlers
    if (my ($handler,$text) = /^=pod:($PODHANDLERS)\s*(.*)/) {
      if ($handler eq 'sub') {
        $method = _mkmethod($pkg, $text);
      } else {
        $$pkg{$handler} = $text;
      }
      $into = $handler;
      $slurp = 1;
      next;
    }

    $slurp and /^=(cut|test|pod)/ and $slurp = 0;

    # Process POD comments
    if( $slurp ) {
      if ($into eq 'sub') {
        _append_line($$method{'description'}, $_);
      } elsif ($into =~ /test|result/) {
        s/^=result ?(.*)$/$1/ and do {
          chomp;
          $into = 'result';
          if ($_) {
            $$t{$into} .= $_;
            $into = '';
          }
        };
        s/^\s{2}// if ($into eq 'result');
        if ($into && $_) {
          $$t{$into} and $$t{$into} .= "\n";
          $$t{$into} .= $_;
        }
      } else {
        _append_line($$pkg{$into}, $_);
      }
      next;
    }

    my ($syntax,$not,$comparator,$match,$result,$test)
      = /^(\=|#\|)test\((\!?)($TESTS)(,([^\)]*))?\)\s*(.*)/;

    if( ($syntax||'') eq '=' ) {
      $slurp = 1;
      $into = 'test';
    }
    $comparator and do {
      my ($summary) = $test =~ /^\s*#\s*(.*)/;
      if( $summary ) {
        $test = '';
      } else {
        ($summary) = $test =~ /;\s*#\s*(.*)\Z/m;
        $summary and $test =~ s/;\s*#\s*(.*)\Z/;/m;
      }
      $summary and $summary =~ s/(?!\\)\'/\\'/g;
      $test =~ s/^\s+//;
      $t = {
        'lib'           => $path,
        'num'           => $#$tests + 2,
        'comparator'    => $comparator,
        'summary'       => $summary || '',
        'test'          => $test ? "  $test" : '',
        'result'        => defined $result ? $result : '',
        'package'       => $pkg->{'name'},
        'lineno'        => $lineno,
        'invert'        => $not ? 1 : 0,
      };
      push @$tests, $t;
      if ($method) {
        push @{$method->{tests}}, $t;
      } else {
        push @{$pkg->{tests}}, $t;
      }
      next;
    };
    s/^#\|\s*// and do {
      $$t{'test'} and $$t{'test'} .= "\n";
      $$t{'test'} .= "  $_";
      next;
    };
    s/^#=(.*)/$1/ and do {
      $$t{'result'} and $$t{'result'} .= "\n";
      $$t{'result'} .= $_;
      next;
    };
    s/^#~// and do {
      s/^[\s'"]+//g;
      s/(<?!\\)[\s'"]+$//g;
      if ($_) {
        $$t{'result'} and $$t{'result'} .= "\n";
        $$t{'result'} .= $_;
      }
      next;
    };
    # Comments which begin at char 0
    if (s/^#\s?//) {
      /^[-=]+$/ and next; # ignore '# ----' and '# ====' separators
      if ($method) {
        unless ($$method{'name'}) {
          throw Error::Logical "Body without header: $path line $lineno)";
          undef $method;
          next;
        }
        if (/^$$method{'name'}/) {
        } else {
          /\w+:$/ and $_ .= "\n"; # don't join next line - eg, 'where:'
#         $$method{'description'} .= "$_\n";
          _append_line($$method{'description'}, $_);
        }
      } else {
        $method = _mkmethod($pkg, $_);
      }
    } else {
      next unless $method;
      next unless /\w/;
      next if $slurp;
      undef $method;
    }
  }
}

sub _mkmethod {
  my ($pkg, $text) = @_;
  my ($name, $summary) = $text =~ /^([^\s\-]+) - (.*)/;
  return unless $name;
  my $access = $name =~ /^_|^[A-Z]+$/ ? 'private' : 'public';
  my $result = {
    'name'          => $name,
    'summary'       => $summary,
    'access'        => $access,
    'usage'         => '',
    'description'   => '',
    'tests'         => [],
  };
  push @{$$pkg{'methods'}{$access}}, $result;
  return $result;
}

1;

__END__

=pod:summary

  Extract documentation and test cases from a properly annotated file

=pod:synopsis

  use Perl::ModuleInfo;
  my $info = Perl::ModuleInfo->new();
  $info->parse('./lib', 'Local/Example.pm');
  $info->parse('./lib', 'Local/Sample.pm');

=pod:description

Extract documentation and test cases from a properly annotated file.

Shortcut POD annotations:

These C<=pod> annotations must begin the line with no leading white space.

  =pod:summary        The part which comes after the package NAME
  =pod:synopsis       The SYNOPSIS section
  =pod:description    The DESCRIPTION section
  =pod:seealso        The SEE ALSO section
  =pod:sub            Documentation for a subroutine

Example:

  package Local::Example;

  # say_hello - Print a greeting
  # The normal way to document a method
  sub say_hello {
    printf "%s\n", 'Hello';
  }

  sub say_goodbye {
    printf "%s\n", 'Goodbye';
  }

  1;

  =pod:summary

    An example module

  =pod:synopsis

    use Local::Example;

  =pod:description

  This example module does nothing of interest.

  =pod:seealso

  The L<Perl::ModuleInfo> module

  =pod:sub say_goodbye - Print a parting

  Another way to write the documentation for a method.

  =cut

Test cases:

For test written with POD annotations C<=test> and C<=result>, the C<=result>
body must begin with two and only two spaces. Any additional leading spaces
are considered part of the actual test result.

=cut
