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

    # Begin new package
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
        $$method{'description'} .= "$_\n";
      } elsif ($into =~ /test|result/) {
        s/^=result ?(.*)$/$1/ and do {
          chomp;
          $into = 'result';
          if ($_) {
            $$t{$into} .= $_;
            $into = '';
          }
        };
#       s/^[\s'"]*(.*)[\s'"]*$/$1/ if ($into eq 'result');
        s/^\s{2}// if ($into eq 'result');
        if ($into && $_) {
          $$t{$into} and $$t{$into} .= "\n";
          $$t{$into} .= $_;
        }
      } else {
        $$pkg{$into} .= "$_\n";
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
          $$method{'usage'} .= $_ ? "  $_\n" : "\n";
        } else {
          /\w+:$/ and $_ .= "\n"; # don't join next line - eg, 'where:'
          $$method{'description'} .= "$_\n";
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
