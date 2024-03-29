=head1 NAME

XAO::DO::Web::FilloutForm - support for HTML forms

=head1 DESCRIPTION

Fill out form object. Helps to create fill-out forms for registration
and so on. Checks that parameters are Ok and then displays either form
or thanks.

Must be overriden with something which will put 'fields' parameter
into $self. Format is as array of hash references reference of the
following structure:

 [ { name       => field name,
     required   => 0 || 1,
     style      => selection || text || email || phone || integer ||
                   dollars || real,
     maxlength  => maximum length,
     minlength  => minimum length,
     param      => name of parameter for form substitution,
     text       => description of parameter,
   },
   { ... }
 ]

If you do not care in what order fields are checked you can also
supply 'fields' as a hash reference:

 { name => {
       required     => 0 || 1,
       style        => text || email || phone || integer || dollars || real,
       maxlength    => maximum length,
       minlength    => minimum length,
       param        => name of parameter for form substitution,
       text         => description of parameter,
   },
   name1 => { ... }
 }

When form filled out "form_ok" method is called, which must be
overridden in inherited object to do something good with
results. Alternatively reference to subroutine can be given through
'setup' method. This is suitable for using FilloutForm object without
overriding it.

Displays form with PARAM.VALUE set to value, PARAM.NAME - to name,
PARAM.TEXT - to text and PARAM.HTML - to piece of HTML code if
applicable (Country selection for example).

=head1 METHODS

=over

=cut

###############################################################################
package XAO::DO::Web::FilloutForm;
use strict;
use XAO::Utils qw(:args :debug :html);
use XAO::Errors qw(XAO::DO::Web::FilloutForm);
use base XAO::Objects->load(objname => 'Web::Page');

use vars qw($VERSION);
$VERSION=(0+sprintf('%u.%03u',(q$Id: FilloutForm.pm,v 2.1 2005/01/14 01:39:57 am Exp $ =~ /\s(\d+)\.(\d+)\s/))) || die "Bad VERSION";

sub setup ($%);
sub field_desc ($$);
sub display ($;%);
sub form_ok ($%);
sub form_phase ($);
sub check_form ($%);
sub pre_check_form ($%);
sub countries_list ();
sub us_continental_states_list ();
sub us_states_list ();
sub cc_list ($);
sub cc_validate ($%);
sub calculate_year ($$);

###############################################################################

=item new (%)

Overrided new method for those who prefer to use inheritance style.

=cut

sub new ($%) {
    my $proto=shift;
    my $class=ref($proto) || $proto;
    my $args=get_args(\@_);
    my $self=$proto->SUPER::new($args);

    ##
    # Setting up fields if required
    #
    $self->setup_fields(fields => $args->{fields},
                        values => $args->{values}) if $args->{fields};

    ##
    # Done
    #
    $self;
}

##
# Setting object up for use as embedded form checker from other
# non-derived objects.
#
# Arguments are:
#  fields =>         fields descriptions
#  values =>	     values for fields, unless this is set all values
#                    are cleaned
#  extra_data =>     reference to any data, subroutines will then be
#                    able to access it.
#  form_ok =>        form_ok subroutine reference (mandatory)
#  pre_check_form => pre_check_form subroutine reference 
#  check_form =>     check_form subroutine reference
#  submit_name =>    name of the submit button
#  keep_form =>      display form template even when the form is complete
#
# Call to this subroutine is not required from derived objects, use
# method overriding instead when possible!
#
sub setup ($%) {
    my $self=shift;
    my $args=get_args(\@_);

    ##
    # Fields and values
    #
    $self->setup_fields(fields => $args->{fields},
                        values => $args->{values});

    ##
    # Handlers and special data:
    #  extra_data  - passed to handlers as is.
    #  submit_name - name of submit button for pre-filled forms (change form).
    #
    my @names=qw(extra_data submit_name form_ok pre_check_form check_form keep_form);
    @{$self}{@names}=@{$args}{@names};
    my $values=$args->{values} || {};
    foreach my $fdata (@{$self->{fields}}) {
        $fdata->{value}=$values->{$fdata->{name}};
    }
}

###############################################################################

=item setup_fields (%)

Copying fields descriptions. We copy entire structure here because it
could be persistent and we do not want original data to be modified.

=cut

sub setup_fields ($%) {
    my $self=shift;
    my $args=get_args(\@_);
    my $fields=$args->{fields};
    return unless $fields && ref($fields);

    my $values=$args->{values};
    my @copy;
    foreach my $fdata (ref($fields) eq 'ARRAY' ? @{$fields}
                                               : keys %{$fields}) {
        my $name;
        if(! ref($fdata)) {
            $name=$fdata;
            $fdata=$fields->{$name};
            $fdata->{name}=$name;
        }
        else {
            $name=$fdata->{name};
        }

        my %cd;
        @cd{keys %{$fdata}}=values %{$fdata};
        $cd{value}=$values->{$name} if $values && $values->{$name};
        push(@copy,\%cd);
    }

    $self->{fields}=\@copy;
}

###############################################################################

=item display (%)

Displaying the form.

=cut

sub display ($;%) {
    my $self=shift;
    my $args=get_args(\@_);
    my $cgi=$self->cgi;
    my $fields=$self->{fields};
    $fields || throw XAO::E::DO::Web::FilloutForm
                     "display - has not set fields for FilloutForm";
    my $phase=$self->{phase}=$args->{phase};
    $self->{submit_name}=$args->{submit_name} if $args->{submit_name};

    ##
    # Checking the type of fields argument we have - hash or
    # array? Converting to array if it is a hash.
    #
    if(ref($fields) eq 'HASH') {
        my @newf;
        foreach my $name (keys %{$fields}) {
            $fields->{$name}->{name}=$name;
            push @newf,$fields->{$name};
        }
        $self->{fields}=$fields=\@newf;
    }

    # Pre-checking form with external overridable function.
    #
    $self->pre_check_form($args);

    # Displayable object
    #
    my $obj=$self->object;

    # First checking all parameters and collecting mistakes into errstr.
    #
    # Also creating hash with parameters for form diplaying while we are
    # going through fields anyway.
    #
    my $errstr;
    my %formparams;
    my $have_cgivalues=0;
    foreach my $fdata (@{$fields}) {
        my $name=$fdata->{name};
        my $cgivalue=$cgi->param($name);
        $have_cgivalues++ if defined($cgivalue) &&
                             (!defined($fdata->{phase}) ||
                              $fdata->{phase} eq $phase);

        ##
        # Checking form phase for multi-phased forms if required.
        #
        next if defined($fdata->{phase}) && $phase<$fdata->{phase};

        my $value=$fdata->{newvalue};
        $value=$cgivalue unless defined($value);
        $value=$fdata->{value} unless defined($value);
        $value=$fdata->{default} unless defined($value);

        ##
        # Empty data is the same as undefined. Spaces are trimmed from the
        # beginning and the end of the string.
        #
        $value="" unless defined $value;
        $value=~s/^\s*(.*?)\s*$/$1/g;

        ##
        # Various checks depending on field style.
        #
        my $newerr;
        my $style=$fdata->{style};
        if(!length($value) && $fdata->{required}) {
            $newerr=$self->Tx('Required field!');
        }
        elsif($fdata->{maxlength} && length($value) > $fdata->{maxlength}) {
            $newerr=$self->Tx('Value is too long!');
        }
        elsif($fdata->{minlength} && length($value) &&
              length($value) < $fdata->{minlength}) {
            $newerr=$self->Tx("Value is too short!");
        }
        elsif($style eq 'text') {
            # No checks for text
        }
        elsif($style eq 'email') {
            if(length($value) && $value !~ /^.*\@([a-z0-9-]+\.)+[a-z]+$/i) {
                $newerr=$self->Tx("Value is not in the form of user\@host.domain!");
            }
        }
        elsif($style eq 'usphone') {
            $fdata->{maxlength}=15 unless $fdata->{maxlength};
            if(length($value)) {
                $value =~ s/\D//g;
                if(length($value) == 7) {
                    $newerr=$self->Tx("Needs area code!");
                }
                elsif(length($value) == 11) {
                    if(substr($value,0,1) ne '1') {
                        $newerr=$self->Tx("Must be a US phone!");
                    }
                }
                elsif(length($value) != 10) {
                    $newerr=$self->Tx("Does not look like a right phone!");
                }
                else {
                    $value=~s/^.?(...)(...)(....)/($1) $2-$3/;
                }
            }
        }
        elsif($style eq 'phone') {      # +99 (123) 456-78-90 x 123
            $fdata->{maxlength}=30 unless $fdata->{maxlength};
            if(length($value)) {
                my ($p,$e)=split(/[a-zA-Z]+/,$value);

                $p=~s/\D//g;
                $e||='';
                $e=~s/\D//g;

                if(length($p)<10) {
                    $newerr=$self->Tx("Needs area code!");
                }
                elsif(length($p)==10) {
                    $p='1' . $p;
                }
                elsif(length($p)>13) {
                    $newerr=$self->Tx("Too many digits!");
                }

                if(!$newerr) {
                    ($value=$p)=~s/^(.+)(...)(...)(....)$/+$1 ($2) $3-$4/;
                    $value.=" ext. $e" if $e;
                }
            }
        }
        elsif($style eq 'int' || $style eq 'integer' || $style eq 'number') {
            if(length($value)) {
                if($value =~ /^[\d,']+$/) {
                    $value=~s/[,']+//g;
                    if(defined($fdata->{minvalue}) && $value<$fdata->{minvalue}) {
                        $newerr=$self->Tx("Value is less than {{min}}",
                                            { min => $fdata->{minvalue} });
                    }
                    if(defined($fdata->{maxvalue}) && $value>$fdata->{maxvalue}) {
                        $newerr=$self->Tx("Value is greater than {{max}}",
                                            { max => $fdata->{maxvalue} });
                    }
                }
                else {
                    $newerr=$self->Tx("Is not an integer!");
                }
            }
        }
        elsif($style eq 'real') {
            if(length($value)) {
                if($value =~ /^[\d,'\.]+$/) {
                    $value=~s/[,']+//g;
                    if(defined($fdata->{minvalue}) && $value<$fdata->{minvalue}) {
                        $newerr=$self->Tx("Value is less than {{min}}",
                                            { min => $fdata->{minvalue} });
                    }
                    if(defined($fdata->{maxvalue}) && $value>$fdata->{maxvalue}) {
                        $newerr=$self->Tx("Value is greater than {{max}}",
                                            { max => $fdata->{maxvalue} });
                    }
                }
                else {
                    $newerr=$self->Tx("Is not an number!");
                }
            }
        }
        elsif($style eq 'password') {
            if(length($value) && $fdata->{pair} &&
               $value ne $cgi->param($fdata->{pair})) {
                $newerr=$self->Tx("Does not match the copy!");
            }
        }
        elsif($style eq 'country') {
            my @cl=$self->countries_list();
            my $match=0;
            foreach my $c (@cl) {
                $match=lc($c) eq lc($value);
                last if $match;
            }
            if(length($value) && !$match) {
                $newerr=$self->Tx("Unknown country");
            }
        }
        elsif($style eq 'usstate' || $style eq 'uscontst') {
            my @cl=$style eq 'usstate' ? $self->us_states_list()
                                       : $self->us_continental_states_list();
            my $match=0;
            my $sv=substr($value || '',0,2);
            foreach my $c (@cl) {
                $match=lc(substr($c,0,2)) eq lc($sv);
                last if $match;
            }
            if(length($value) && !$match) {
                $newerr=$self->Tx("Unknown state");
            }
        }
        elsif($style eq 'cctype') {
            my @cl=$self->cc_list();
            my $match=0;
            foreach my $c (@cl) {
                $match=lc($c) eq lc($value);
                last if $match;
            }
            if(length($value) && !$match) {
                $newerr=$self->Tx("Unknown credit card type");
            }
        }  
        elsif($style eq 'ccnum') {
            if(length($value)) {
                my $type=$fdata->{pair} ? $cgi->param($fdata->{pair}) : '';
                $newerr=$self->cc_validate(type => $type, number => $value, validated => \$value);
            }
        }
        elsif($style eq 'month') {
            if(length($value)) {
                $value=int($value);
                if($value<1 || $value>12) {
                    $newerr=$self->Tx('Invalid month!');
                }
            }
        }
        elsif($style eq 'year') {
            if($fdata->{minyear} && $fdata->{maxyear}) {
                my $minyear=$self->calculate_year($fdata->{minyear});
                my $maxyear=$self->calculate_year($fdata->{maxyear});
                if(length($value)) {
                    $value=$self->calculate_year($value);
                    if($value<$minyear) {
                        $newerr=$self->Tx("Must be after {{year}}",
                                            { year => $minyear });
                    }
                    elsif($value>$maxyear) {
                        $newerr=$self->Tx("Must be before {{year}}",
                                            { year => $maxyear });
                    }
                }
            }
            elsif(length($value)) {
                $value=$self->calculate_year($value);
                if($value<1900 || $value>2099) {
                    $newerr=$self->Tx('Invalid year!');
                }
            }
        }
        elsif($style eq 'checkbox') {

            ##
            # If checkbox is not checked we don't get any info about it
            # in the cgi parameters. So we have to take a guess if the
            # form was generally filled in, but we have an unchecked
            # checkbox or this is the first display and form was not
            # submitted yet.
            #
            if($have_cgivalues) {
                $value=$cgivalue ? 1 : 0;
            }
            else {
                $value=(defined($fdata->{value}) ? $fdata->{value} : $fdata->{default}) ? 1 : 0;
            }
        }
        elsif($style eq 'selection') {
            if(length($value)) {
                my $opt=$fdata->{options};
                if(ref($opt) eq 'HASH') {
                    if(!defined $opt->{$value}) {
                        $newerr=$self->Tx('Bad option value!');
                    }
                }
                elsif(ref($opt) eq 'ARRAY') {
                    my $found;
                    for(my $i=0; $i<@$opt; $i+=2) {
                        next unless defined($opt->[$i+1]);
                        if($opt->[$i] eq $value) {
                            $found=1;
                            last;
                        }
                    }
                    if(!$found) {
                        $newerr=$self->Tx('Bad option value!');
                    }
                }
                else {
                    $newerr=$self->Tx('Unknown data in options!');
                }
            }
        }
        else {
            $self->throw("display - unknown style '$style'");
        }

        # Generating HTML for some field styles.
        #
        my $param=$fdata->{param} || uc($name);
        if($style eq 'country') {
            my @cl=$self->countries_list();
            my $html='';
            foreach my $c (@cl) {
                my $sel=(lc($c) eq lc($value)) ? " SELECTED" : "";
                $html.="<OPTION$sel>".t2ht($c)."</OPTION>\n";
            }
            $fdata->{html}=qq(<SELECT NAME=$name><OPTION VALUE="">Select Country</OPTION>$html</SELECT>);
        }
        elsif($style eq 'usstate' || $style eq 'uscontst') {
            my @cl=$style eq 'usstate' ? $self->us_states_list()
                                       : $self->us_continental_states_list();
            my $html='';
            my $stv=lc(substr($value,0,2));
            foreach my $c (@cl) {
                my $sel=(lc(substr($c,0,2)) eq $stv) ? " SELECTED" : "";
                $html.="<OPTION$sel>".t2ht($c)."</OPTION>\n";
            }
            $formparams{"$param.HTML_OPTIONS"}=$html;
            $fdata->{html}=qq(<SELECT NAME=$name><OPTION VALUE="">Select State</OPTION>$html</SELECT>);
        }
        elsif($style eq 'cctype') {
            my @cl=$self->cc_list();
            my $html='';
            foreach my $c (@cl) {
                my $sel=(lc($c) eq lc($value)) ? " SELECTED" : "";
                $html.="<OPTION$sel>".t2ht($c)."</OPTION>\n";
            }
            $fdata->{html}=qq(<SELECT NAME=$name><OPTION VALUE="">Select Card Type</OPTION>$html</SELECT>);
        }  
        elsif($style eq 'month') {
            my @cl=qw(January February March April May June July
                      August September October November December);
            my $html='';
            for(my $i=0; $i!=12; $i++) {
                my $sel=($value && $value == $i+1) ? " SELECTED" : "";
                $html.=sprintf("<OPTION VALUE=\"%02u\"$sel>%02u - %s</OPTION>\n",$i+1,$i+1,$cl[$i]);
            }
            $fdata->{html}=qq(<SELECT NAME=$name><OPTION VALUE="">Select Month</OPTION>$html</SELECT>);
        }
        elsif($style eq 'year' && !$fdata->{maxlength} && $fdata->{minyear} && $fdata->{maxyear}) {
            my $minyear=$self->calculate_year($fdata->{minyear});
            my $maxyear=$self->calculate_year($fdata->{maxyear});
            my $html='';
            for(my $i=$minyear; $i<=$maxyear; $i++) {
                my $sel=($value && $value == $i) ? " SELECTED" : "";
                $html.=sprintf("<OPTION VALUE=\"%04u\"$sel>%04u</OPTION>\n",$i,$i);
            }
            $html=qq(<SELECT NAME="$name"><OPTION VALUE="">Select Year</OPTION>$html</SELECT>);
            $fdata->{html}=$html;
        }
        elsif($style eq 'checkbox') {
            $fdata->{html}=$obj->expand(
                path    => '/bits/fillout-form/html-checkbox',
                NAME    => $name,
                VALUE   => $fdata->{value} || '',
                CHECKED => $value,
            );
        }
        elsif($style eq 'selection') {
            my $opt=$fdata->{options} ||
                $self->throw("display - no 'options' for '$name' selection");

            my $has_empty;
            my $used_selected;
            my $html='';
            my $html_sub=sub {
                my ($v,$t)=@_;
                $has_empty=1 if !length($v);
                return unless defined($t);
                my $sel='';
                if(!$used_selected && $value eq $v) {
                    $sel=' SELECTED';
                    $used_selected=1;
                }
                my $vh=t2hf($v);
                $html.=qq(<OPTION VALUE="$vh"$sel>) .
                       t2ht($t) .
                       '</OPTION>';
                $formparams{"$param.RV_CURRENT_$vh"}=$sel ? 1 : 0;
                $formparams{"$param.RV_VALUE_$vh"}=$v;
                $formparams{"$param.RV_TEXT_$vh"}=$t;
            };

            if(ref($opt) eq 'HASH') {
                foreach my $v (sort { $opt->{$a} cmp $opt->{$b} } keys %$opt) {
                    &{$html_sub}($v,$opt->{$v});
                }
            }
            elsif(ref($opt) eq 'ARRAY') {
                for(my $i=0; $i<@$opt; $i+=2) {
                    &{$html_sub}($opt->[$i],$opt->[$i+1]);
                }
            }
            else {
                throw $self "Unknown data type in 'options' name=$name";
            };

            ##
            # We do not display 'Please select' if there is an empty
            # value in the list, we assume that that empty value is a
            # prompt of some sort.
            #
            # If there is no need for empty value and no need for a
            # prompt -- use ('' => undef) as an indicator of that.
            #
            $formparams{"$param.HTML_OPTIONS"}=$html;
            $fdata->{html}='<SELECT NAME="' . t2hf($name) . '">' .
                           ($has_empty ? '' : '<OPTION VALUE="">Please select</OPTION>') .
                           $html .
                           '</SELECT>';
        }
        elsif($style eq 'text' || $style eq 'phone' || $style eq 'usphone' ||
              $style eq 'ccnum' || $style eq 'email' || $style eq 'year' ||
              $style eq 'number' || $style eq 'int' || $style eq 'integer' ||
              $style eq 'real') {
            $fdata->{html}=$obj->expand(
                path => '/bits/fillout-form/html-text',
                NAME => $name,
                VALUE => $value || '',
                MAXLENGTH => $fdata->{maxlength} || 100,
                SIZE => $fdata->{size} || 30,
            );
        }
        elsif($style eq 'password') {
            $fdata->{html}=$obj->expand(
                path => '/bits/fillout-form/html-password',
                NAME => $name,
                VALUE => $value || '',
                MAXLENGTH => $fdata->{maxlength} || 100,
                SIZE => $fdata->{size} || 30,
            );
        }

        ##
        # Adding error description to the list if there was an
        # error. Storing value otherwise.
        #
        if($newerr) {
            $errstr.=($fdata->{text} || $name) .  ": " . $newerr . "<BR>\n";
            $fdata->{errstr}=$newerr;
        }
        else {
            $fdata->{value}=$value;
        }

        ##
        # Filling formparams hash
        #
        $formparams{"$param.VALUE"}=defined($value) ? $value : "";
        $formparams{"$param.TEXT"}=$fdata->{text} || $name;
        $formparams{"$param.NAME"}=$name;
        $formparams{"$param.HTML"}=$fdata->{html} || "";
        $formparams{"$param.SIZE"}=$fdata->{size} || 30;
        $formparams{"$param.MAXLENGTH"}=$fdata->{maxlength} || 0;
        $formparams{"$param.MINLENGTH"}=$fdata->{minlength} || 0;
        $formparams{"$param.ERRSTR"}=$fdata->{errstr} || '';
    }

    # Special parameter named 'submit_name' contains submit button name
    # and used for pre-filled forms - these forms usually already have
    # valid data and we need some way to know when the form was really
    # checked and corrected by user.
    #
    if($self->{submit_name}) {
        $have_cgivalues=$cgi->param($self->{submit_name}) ? 1 : 0;
    }

    # Checking content for general compatibility by overriden
    # method. Called only if data are basicly good.
    #
    if($have_cgivalues && !$errstr) {
        ($errstr,my $fname)=$self->check_form(merge_refs($args,\%formparams));
        if($fname) {
            my $fdata=$self->field_desc($fname);
            my $param=$fdata->{param} || uc($fdata->{name});
            $fdata->{errstr}=$formparams{"$param.ERRSTR"}=$errstr || '';
        }
        else {
            $formparams{"ERRSTR.CHECK_FORM"}=$errstr;
        }
    }
    $formparams{"ERRSTR.CHECK_FORM"}||='';

    # If the form is not filled at all we remove errstr's from
    # individual fields.
    #
    if(!$have_cgivalues) {
        foreach my $fdata (@{$fields}) {
            my $param=$fdata->{param} || uc($fdata->{name});
            $formparams{"$param.ERRSTR"}='';
        }
    }

    ##
    # If there were errors then displaying the form. We also display
    # the form here if it is not yet filled out and if it is, but we we
    # asked to keep displaying it using 'keep_form' setup parameter.
    #
    my $keep_form=$self->{keep_form};
    if(!$have_cgivalues || $errstr || $keep_form) {
        my $eh;
        my $et;
        if($errstr && $have_cgivalues) {
            $eh=$obj->expand(
                path => '/bits/fillout-form/errstr',
                ERRSTR => $errstr,
                'ERRSTR.CHECK_FORM' => $formparams{"ERRSTR.CHECK_FORM"},
            );
            $et=$errstr;

        }
        $obj->display(merge_refs($args,{
            path          => $args->{'form.path'},
            template      => $args->{'form.template'},
            ERRSTR        => $et || '',
            'ERRSTR.HTML' => $eh || '',
            %formparams,
        }));
        return unless $keep_form && !$errstr && $have_cgivalues;
    }

    ##
    # Our form is correct!
    #
    $self->form_ok(merge_refs($args,\%formparams));
}

###############################################################################

=item field_desc ($)

Returns field description by name. This is the correct way to get to the
value of a field from check_form() or form_ok() methods.

=cut

sub field_desc ($$) {
    my $self=shift;
    my $name=shift;
    my $fields=$self->{fields};
    $fields || throw XAO::E::DO::Web::FilloutForm
                     "field_desc - has not set fields for FilloutForm";
    if(ref($fields) eq 'ARRAY') {
        foreach my $fdata (@{$fields}) {
            return $fdata if $fdata->{name} eq $name;
        }
    }
    else {
        return $fields->{$name} if $fields->{$name};
    }
    throw XAO::E::DO::Web::FilloutForm "field_desc - unknown field '$name' referred";
}

##
# Default handler for filled out form. Must be overriden!
#
sub form_ok ($%) {
    my $self=shift;
    if($self->{form_ok}) {
        my %na=%{get_args(\@_)};
        $na{extra_data}=$self->{extra_data};
        return &{$self->{form_ok}}($self,\%na);
    }
    $self->throw('form_ok - must be overriden in derived class or using form_ok parameter');
}

##
# High-level form content check. Should be overriden for real checks.
# Returns '' if there were no error or error text otherwise.
#
sub check_form ($%) {
    my $self=shift;
    if($self->{check_form}) {
        my %na=%{get_args(\@_)};
        $na{extra_data}=$self->{extra_data};
        return &{$self->{check_form}}($self,\%na);
    }
    '';
}

###############################################################################

=item pre_check_form (%)

Pre-checking form. May be used if some values are calculated or copied
from another and should be checked later.

Should stuff generated values into {newvalue} parameter.

=cut

sub pre_check_form ($%) {
    my $self=shift;
    if($self->{pre_check_form}) {
        my $na=get_args(\@_);
        $na->{extra_data}=$self->{extra_data};
        return &{$self->{pre_check_form}}($self,$na);
    }
}

###############################################################################

=item countries_list ()

Returns list of countries for selection. May be overriden if site
needs only a fraction of that.

=cut

sub countries_list () {
    split(/\n/,<<'END_OF_LIST');
United States
Afghanistan
Albania
Algeria
American Samoa
Andorra
Angola
Anguilla
Antarctica
Antigua
Antilles
Arab Emirates
Argentina
Armenia
Aruba
Australia
Austria
Azerbaidjan
Bahamas
Bahrain
Bangladesh
Barbados
Barbuda
Belarus
Belgium
Belize
Benin
Bermuda
Bhutan
Bolivia
Bosnia Herz.
Botswana
Bouvet Isl.
Brazil
Brunei Dar.
Bulgaria
Burkina Faso
Burundi
C. African Rep.
Cambodia
Cameroon
Cambodia
Cameroon
Canada
Cape Verde
Cayman Islands
Chad
Chile
China
Christmas Isl.
Cocos Islands
Colombia
Comoros
Congo
Cook Islands
Costa Rica
Croatia
Cuba
Cyprus
Czech Republic
Denmark
Djibouti
Dominica
Dominican Rep.
East Timor
Ecuador
Egypt
England
El Salvador
Equat. Guinea
Eritrea
Estonia
Ethiopia
Falkland Isl.
Faroe Islands
Fiji
Finland
Former Czech.
Former USSR
France
French Guyana
French S. Terr.
Gabon
Gambia
Georgia
Germany
Ghana
Gibraltar
Great Britain
Greece
Greenland
Grenada
Guadeloupe
Grenada
Guadeloupe
Guam (USA)
Guatemala
Guinea
Guinea Bissau
Guyana
Haiti
Heard/McDonald
Honduras
Hong Kong
Hungary
Iceland
India
Indonesia
Iran
Iraq
Ireland
Israel
Italy
Ivory Coast
Jamaica
Japan
Jordan
Kazakhstan
Kenya
Kiribati
Kuwait
Kyrgyzstan
Laos
Latvia
Lebanon
Lesotho
Liberia
Libya
Liechtenstein
Lithuania
Luxembourg
Macau
Macedonia
Madagascar
Malawi
Malaysia
Maldives
Mali
Malta
Marshall Isl.
Martinique
Mauritania
Mauritius
Mayotte
Mexico
Mayotte
Mexico
Micronesia
Moldavia
Monaco
Mongolia
Montserrat
Morocco
Mozambique
Myanmar
N. Mariana Isl.
Namibia
Nauru
Nepal
Netherlands
Neutral Zone
New Caledonia
New Zealand
Nicaragua
Niger
Nigeria
Niue
Norfolk Island
Northern Ireland
North Korea
Norway
Oman
Pakistan
Palau
Panama
Papua New Guinea
Paraguay
Peru
Philippines
Pitcairn Isl.
Poland
Polynesia
Portugal
Puerto Rico
Qatar
Reunion
Romania
Russia
Rwanda
Samoa
San Marino
Saudi Arabia
Scotland
Senegal
Seychelles
Sierra Leone
Singapore
Sierra Leone
Singapore
Slovak Rep.
Slovenia
Solomon Isl.
Somalia
South Africa
South Korea
Spain
Sri Lanka
St Helena
St Lucia
St Pierre
St Tome
St Vincent
Sudan
Suriname
Swaziland
Sweden
Switzerland
Syrian Arab Republic
Tadjikistan
Taiwan
Tanzania
Thailand
Tobago
Togo
Tokelau
Tonga
Trinidad & Tobago
Tunisia
Turopaque
Turkmenistan
Turks/Caicos Isl.
Tuvalu
Uganda
Ukraine
Uruguay
Uzbekistan
Vanuatu
Vatican City
Venezuela
Vietnam
Virg.Isl. (UK)
Virg.Isl. (US)
Wales
Western Sahara
Yemen
Yugoslavia
Zaire
Zambia
Zimbabwe
END_OF_LIST
}

###############################################################################

=item us_continental_states_list ()

Returns list of US continental states for selection. May be overriden
if site needs only a fraction of that.

=cut

sub us_continental_states_list () {
    my $self=shift;
    my @list;
    foreach my $st ($self->us_states_list) {
        next if $st =~ /^AK/;
        next if $st =~ /^AS/;
        next if $st =~ /^FM/;
        next if $st =~ /^GU/;
        next if $st =~ /^HI/;
        next if $st =~ /^MH/;
        next if $st =~ /^MP/;
        next if $st =~ /^RI/;
        next if $st =~ /^VI/;
        push(@list,$st);
    }
    @list;
}

###############################################################################

=item us_states_list ()

Returns list of US states for selection. May be overriden if site
needs only a fraction of that.

=cut

sub us_states_list () {
    split(/\n/,<<'END_OF_LIST');
AL - Alabama
AK - Alaska
AS - American Samoa
AZ - Arizona
AR - Arkansas
CA - California
CO - Colorado
CT - Connecticut
DE - Delaware
DC - District Of Columbia
FM - Federated States Of Micronesia
FL - Florida
GA - Georgia
GU - Guam
HI - Hawaii
ID - Idaho
IL - Illinois
IN - Indiana
IA - Iowa
KS - Kansas
KY - Kentucky
LA - Louisiana
ME - Maine
MH - Marshall Islands
MD - Maryland
MA - Massachusetts
MI - Michigan
MN - Minnesota
MS - Mississippi
MO - Missouri
MT - Montana
NE - Nebraska
NV - Nevada
NH - New Hampshire
NJ - New Jersey
NM - New Mexico
NY - New York
NC - North Carolina
ND - North Dakota
MP - Northern Mariana Islands
OH - Ohio
OK - Oklahoma
OR - Oregon
PW - Palau
PA - Pennsylvania
PR - Puerto Rico
RI - Rhode Island
SC - South Carolina
SD - South Dakota
TN - Tennessee
TX - Texas
UT - Utah
VT - Vermont
VI - Virgin Islands
VA - Virginia
WA - Washington
WV - West Virginia
WI - Wisconsin
WY - Wyoming
END_OF_LIST
}

##
# Returns a list of known Credit Card types. May be overriden. Should be
# consistent with cc_validate.
#
sub cc_list ($) {
    split(/\n/,<<'END_OF_LIST');
Visa
American Express
MasterCard
Discover
Diner's Club
END_OF_LIST
}

##
# Returns error text if card number is invalid, only checksum and
# consistence with card type is checked.
#
sub cc_validate ($%) {
    my $self=shift;
    my $args=get_args(\@_);
    my $number=$args->{number};
    my $type=$args->{type};

    ##
    # General corrections and checks first.
    #
    $number=~s/\D//g;
    if(length($number)<13) {
        return $self->Tx('Number is too short!');
    }

    ##
    # Checksum first
    #
    my $sum=0;
    for(my $i=0; $i!=length($number)-1; $i++) {
        my $weight = substr($number, -1 * ($i + 2), 1) * (2 - ($i % 2));
        $sum += (($weight < 10) ? $weight : ($weight - 9));
    }
    if(substr($number,-1) ne (10-$sum%10)%10) {
        return $self->Tx('Invalid number!');
    }

    ##
    # Checking card type now
    #
    if($type) {
        my $realtype='';
        if($number =~ /^37/) {
            $realtype='american express';
        }
        elsif($number =~ /^4/) {
            $realtype='visa';
        }
        elsif($number =~ /^5/) {
            $realtype='master\s?card';
        }
        elsif($number =~ /^6/) {
            $realtype='discover';
        }
        else {
            return $self->Tx('Unknown card type!');
        }
        if(lc($type) !~ $realtype) {
            return $self->Tx('Number does not match card type!');
        }
    }

    ${$args->{validated}}=$number if $args->{validated};
    return '';
}

##
# Calculates year - accepts value, +N, -N.
#
sub calculate_year ($$) {
    my $self=shift;
    my $year=shift;
    if(substr($year,0,1) eq '+') {
        $year=(localtime)[5]+1900+substr($year,1);
    }
    elsif(substr($year,0,1) eq '-') {
        $year=(localtime)[5]+1900-substr($year,1);
    }
    elsif($year < 20) {
        $year+=2000;
    }
    elsif($year < 100) {
        $year+=1900;
    }
    $year;
}

##
# Returns form phase for multi-page forms. Taken from 'phase' argument
# to 'display' method.
#
sub form_phase ($) {
    my $self=shift;
    return $self->{phase} || 1;
}

###############################################################################

sub Tx ($$;$) {
    my $self=shift;
    my $text=shift;
    my $values=shift || { };

    if($self->can('Tx_translate')) {
        $text=$self->Tx_translate($text,$values);
    }

    $text=~s/
        \{\{(\w+)\}\}
    /
        exists $values->{$1} ? $values->{$1} : '<UNDEF>'
    /xesg;

    return $text;
}

###############################################################################
1;
__END__

=back

=head1 AUTHORS

Copyright (c) 2005 Andrew Maltsev

Copyright (c) 2001-2004 Andrew Maltsev, XAO Inc.

<am@ejelta.com> -- http://ejelta.com/xao/
