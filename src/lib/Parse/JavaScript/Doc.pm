package Parse::JavaScript::Doc;
use strict;

use Exporter;
use Perl::Module;
use Error::Logical;

our @EXPORT_OK = qw(def_to_html def_to_vim);
our %EXPORT_TAGS = (all => [@EXPORT_OK],);
push our @ISA, qw(Exporter);

our @Scope = (
  [qw(global)],
  [qw(namespace)],
  [qw(class structure)],
  [qw(member function)],
);

sub _depth {
  my $str = $_[0];
  $str =~ y/\.//;
}

sub new {
  my $classname = ref($_[0]) ? ref(shift) : shift;
  bless {defs=>[]}, $classname;
}

sub get {
  my ($self, $id) = @_;
  grep_first(sub {$_->{id} eq $id}, @{$self->{defs}});
}

sub sort {
  my $self = shift;
  my $sorted = [];
  push @$sorted, $_ for (sort {$a->{id} cmp $b->{id}} @{$self->{defs}});
  $self->{defs} = $sorted;
  $self;
}

sub parse {
  my $self = shift;
  my $content = shift;
  my $inspect = 0;
  my $def = undef;
  my @prefix = ('js');
  for (split /\r?\n\r?/, $$content) {

    s/\/\*// and $inspect = 1;
    my $end = s/\s*\*\///;
    next unless $inspect;
    s/^[\s\/]*([\*=#L])?\s?//;
    my $em = $1 || '*';
    my ($tag, $value) = /^@([a-z]+)\s*(.*)/;
    my $append = 1;

    if ($tag) {
      for (my $i = 0; $i < @Scope; $i++) {
        if (grep_first(sub {$_ eq $tag}, @{$Scope[$i]})) {
          $prefix[$i] = $value;
          splice @prefix, $i+1;
          next if $tag eq 'extend';
          my @id = grep {defined && /\w/} @prefix;
          my $id = join('.', @id);
          $def = $self->get($id);
          if (!$def) {
            $def = {
              id => $id,
              depth => _depth($id) + 1,
              type => $tag,
              name => $value,
              content => [],
              props => {},
            };
            push @{$self->{defs}}, $def;
          }
          $append = 0;
          last;
        }
      }
      if ($append && $def) {
        $def->{props}{$tag} ||= [];
        push @{$def->{props}{$tag}}, $value;
        push @{$def->{content}}, [$em, ' ' . $value];
      }
    } else {
      if ($append && $def && !$end) {
        if ($_ || @{$def->{content}}) {
          push @{$def->{content}}, [$em, $_ || ''];
        }
      }
    }

    if ($end) {
      undef $def;
      $inspect = 0;
    };

  }
  $self;
}

sub def_to_vim {
  my $def = shift;
  my $alt = shift;
  my @info = ();
  for (@{$def->{content}}) {
    my ($em, $text) = @$_;
    last unless $text && $text !~ /^\s+/;
    $text =~ s/(?<!\\)(["])/\\$1/g;
    push @info, $text;
  }
  my $info = join(' ', @info);
  my $word = $def->{id};
  $alt and $word =~ s/^js\./$alt\./;
  my $result = '';
  $result .= "'word': " . '"' . $word . '",';
  $result .= "'abbr': " . '"' . $word . '",';
  $result .= "'menu': " . '"' . '<' . ucfirst($def->{type}) . '>' . '",';
  #$result .= "'info': " . '"' . ($info || 'No info available') . '"';
  return $result;
}

sub def_to_html {
  my $def = shift;
  my $result = '';
  my $p = 0;
  my $pre = 0;
  my $nl = 0;
  my $sec_id = $def->{'id'};
  for (@{$def->{content}}) {
    my ($em, $text) = @$_;
    my $out = html_prep($em, $text, $sec_id) . "\n";
    if ($text eq '' || /^\s+$/) {
      $nl = 1;
      next;
    } elsif ($text =~ /^(\s+)/) {
      $result .= "</p>" if $p;
      $result .= "<pre>" unless $pre;
      $result .= "\n" if ($nl && $pre);
      $result .= ' ' unless (length($1) % 2 == 0);
      if ($em ne '=') {
        $out =~ s/\becma\./js\./g;
        if ($em eq 'L') {
          $out =~ s/(js\.[A-Za-z0-9\._]+)/html_link($1,$sec_id)/eg;
        }
      }
      $result .= $out;
      $pre = 1;
      $p = 0;
    } else {
      if ($pre) {
        $result .= '</pre>';
        $pre = 0;
      } elsif ($nl && $p) {
        $result .= "</p>\n<p>";
        $nl = 0;
      }
      if (!$p) {
        $result .= "<p>";
        $p = 1;
      }
      $result .= $out;
      $result .= '<br/>' if $em eq '=';
    }
    $nl = 0;
  }
  $result .= '</pre>' if $pre;
  $result .= '</p>';
  return $result;
}

sub html_prep {
  my ($em, $text, $sec_id) = @_;
  return '' unless defined $text;
  $text =~ s/([<>\[\]\&])/sprintf('&#%d;',ord($1))/eg;
  $text =~ s/\bL&#60;(.*?)&#62;/html_link($1,$sec_id)/ge;
  $text =~ s/\bC&#60;(.*?)&#62;/<code>$1<\/code>/g;
  $text =~ s/\bB&#60;(.*?)&#62;/<b>$1<\/b>/g;
  $text =~ s/\bI&#60;(.*?)&#62;/<i>$1<\/i>/g;
  $text =~ s/\bN&#60;(.*?)&#62;/<dfn id="$sec_id:$1">$1<\/dfn>/g;
  $text = "<strong>$text</strong>" if $em eq '#';
  $text =~ s/\b(TODO|XXX)\b/<em>$1<\/em>/g;
  $text;
}

sub html_link {
  my ($dest,$text) = split /\|/, shift;
  my $sec_id = shift;
  $text ||= $dest;
  if ($dest =~ /^\d$/) {
    return sprintf('<a href="#%s"><cite>%s</cite></a>', "$sec_id:$dest", $text);
  } elsif ($dest =~ /\//) {
    return sprintf('<a target="_top" href="%s">%s</a>', $dest, $text);
  } else {
    if ($dest =~ /^\./) {
      my $base = $sec_id;
      $base =~ s/[^\.]+$//;
      $dest =~ s/^\./$base/;
      $text =~ s/^\.//;
    } else {
      $dest =~ s/^ecma\./js\./;
      $text =~ s/^ecma\./js\./;
    }
    my $href = "#$dest";
    my $fmt = '<code><a href="%s" onclick="return parent._select(event,\'%s\');">%s</a></code>';
    return sprintf($fmt, $href, $dest, $text);
  }
}

1;
