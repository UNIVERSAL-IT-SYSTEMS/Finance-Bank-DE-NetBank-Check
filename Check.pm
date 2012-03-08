package Finance::Bank::DE::NetBank::Check;
use strict;
use warnings;
use Exporter;
use WWW::Mechanize;
use Image::Magick;
use File::Temp qw/ tempfile tempdir /;
our @ISA = qw/Exporter/;
our @EXPORT = qw/netbankcsv/;
our $VERSION = '0.1';

sub netbankcsv {
	my($userid) = shift;
	my($password) = shift;
	my($tesseract) = shift;
	return if(!$userid or !$password or !$tesseract);

	for my $hig (1..3){#Loop for captchas - ~95%
		my $mech = WWW::Mechanize->new( cookie_jar => {} );

		my $url = "http://www.netbank.de/nb/onlinebanking.jsp";
		$mech->get( $url );
		$mech->follow_link( url => 'https://banking.netbank.de/wps/netbank-modern-banking.jsp?blz=20090500&cll=1' );

		my $html = $mech->content;
		my($captcha) = ($html =~ /<img src="([^"]*)" height="20" width="81" alt="Grafisch dargestellter Zugriffscode"/);
		$captcha = 'https://banking.netbank.de'.$captcha if($captcha);

		my $mechcap = $mech->clone();
		$mechcap->get( $captcha );

		my($fh, $file) = tempfile(UNLINK => 0, SUFFIX => '.jpg');
		binmode($fh);
		print $fh $mechcap->content;
		close($fh);

		my $checkdata = netbankcaptcha($file,$tesseract);
		next unless($checkdata);
		unlink($file);

		$mech->submit_form(
			form_number => 1,
			fields      => {
				userid    => $userid,
				password    => $password,
				accesscode    => $checkdata
			}
		);
		my $result = $mech->content;
		if($hig == 1 or $hig == 2){
			next if($result !~ /Ihre letzte Anmeldung/);
		}else{
			die "False Login!" if($result !~ /Ihre letzte Anmeldung/);
		}
		my($gesamtsaldo) = ($result =~ /<span class="gesamtsaldobetrag saldo-positive">([^<]*)<\/span>/);

		my($H_iban) = ($result =~ /<div id="iban">(.*?)<\/div>/s);
		my($H_bic) = ($result =~ /<div id="bic">(.*?)<\/div>/s);
		my($H_owner) = ($result =~ /<div id="owner">(.*?)<\/div>/s);
		my($H_number) = ($result =~ /<div id="number">(.*?)<\/div>/s);
		my($H_institute) = ($result =~ /<div id="institute">(.*?)<\/div>/s);

		my($iban) = ($H_iban =~ /<span class="value info">([^<]*)<\/span>/);
		my($bic) = ($H_bic =~ /<span class="value info">([^<]*)<\/span>/);
		my($owner) = ($H_owner =~ /<span class="value info">([^<]*)<\/span>/);
		my($number) = ($H_number =~ /<span class="value info">([^<]*)<\/span>/);
		my($institute) = ($H_institute =~ /<span class="value info">([^<]*)<\/span>/);
		my($lastlogin) = ($result =~ /<div id="lastLogin" class="info">([^<]*)<\/div>/);
		$lastlogin =~ s/^Ihre letzte Anmeldung:\s*//g;

		my($java) = ($result =~ /<input type="hidden" name="javax.faces.ViewState" id="javax.faces.ViewState" value="([^"]*)"/);
		my($startform,$newlink) = ($result =~ /<form id="([^"]*startForm)" name="[^"]*" method="post" action="([^"]*)">/);
		$newlink = 'https://banking.netbank.de'.$newlink if($newlink && $newlink =~ /^\//);
		my($not1,$not2,$first,$second) = ($result =~ /<a id="[^"]*" class="button bankingsprites umsatzanzeige tooltipped" title="Umsatzanzeige" href="\#" onclick="return _JSFFormSubmit\('([^']*)','([^']*)',null,\{'([^']*)':'([^']*)'/);
		$first .= ":j_idcl" if($first !~ /idcl$/ && $first);
		die "Data for details not found. $first $second $java $newlink $newlink" if(!$first or !$java or !$newlink or !$startform or !$second);

		my $htmlx = qq~<html><body><form method="post" action="$newlink" enctype="application/x-www-form-urlencoded">
		<input type="hidden" name="autoscroll" value=""><input type="hidden" name="$startform" value="$startform">
		<input type="hidden" name="javax.faces.ViewState" value="$java"><input type="hidden" name="$first" value="$second"><input type="submit" value="OK"></form></body></html>~;
		$mech->update_html($htmlx);
		$mech->submit_form(
			form_number => 1,
		);

		my $result2 = $mech->content;
		my($xls) = ($result2 =~ /<a href="([^"]*xls)" target="_blank" class="tooltipped" title="speichern">/);
		$xls = 'https://banking.netbank.de'.$xls if($xls =~ /^\// && $xls);
		$mech->get($xls);
		my $csv = $mech->content;
		my @newdata;

		foreach my $line (split(/\n/,$csv)){
			if($line =~ /^\"\d/){
				$line =~ s/^"//g;
				$line =~ s/^$//g;
				my($buchungstag,$wertstellungstag,$verwendungszweck,$umsatz,$waehrung) = split(/"\s+"/,$line);
				my %details;
				$details{'buchungstag'} = $buchungstag;
				$details{'wertstellungstag'} = $wertstellungstag;
				$details{'verwendungszweck'} = $verwendungszweck;
				$details{'umsatz'} = $umsatz;
				$details{'waehrung'} = $waehrung;
				push(@newdata,\%details)
			}
		}

		return(\@newdata,({
			'gesamtsaldo' => $gesamtsaldo,
			'iban' => $iban,
			'bic' => $bic,
			'owner' => $owner,
			'number' => $number,
			'institute' => $institute,
			'lastlogin' => $lastlogin
			})
		);
	}
}

sub command {
	my($e) = @_;
	my $return;
	eval {
		local $SIG{ALRM} = sub { die "alarm\n" };
		alarm(5);
		$return = join("",`$e`);
		alarm(0);
	};
	return($return);
}

sub is_pixel_allowed {
	my($level, $pixel) = @_;
	my($red, $green, $blue, $opacity) = split ",", $pixel;
	return (($red <= $level) and ($green <= $level) and ($blue <= $level));
}

sub is_pixel_white {
	my($pixel) = shift;
	my($red, $green, $blue, $opacity) = split ",", $pixel;
	return (($red == 65535) and ($green == 65535) and ($blue == 65535));
}

sub is_pixel_black {
	my($pixel) = shift;
	my($red, $green, $blue, $opacity) = split ",", $pixel;
	return (($red == 0) and ($green == 0) and ($blue == 0));
}

sub netbankcaptcha {
	my %topcap;
	my $myfile = shift;
	my $tesseract = shift;
	return unless(-e($myfile));
	return unless($tesseract);

	foreach my $hig (1..10){
		my $mynewfile = $myfile;
		$mynewfile =~ s/\.jpg$/.tif/g;
		unlink("$mynewfile");
		my $image = new Image::Magick;
		my $x = $image->Read($myfile);
		my($width, $height) = $image->Get('width', 'height'); 

		for my $j (1..$height){
			$image->Set("pixel[0,$j]" => 'white');
			$image->Set("pixel[1,$j]" => 'white');
			$image->Set("pixel[81,$j]" => 'white');
		}

		for my $j (1..$width){
			$image->Set("pixel[$j,0]" => 'white');
			$image->Set("pixel[$j,1]" => 'white');
			$image->Set("pixel[$j,20]" => 'white');
		}

		my $threshold_level = 255 * 75;
		my ($blob) = $image->ImageToBlob(magick=>'RGB', colorspace=>'RGB', depth=>'8');
		my @data = unpack("C*",$blob);

		for my $j (1..$height){
			for my $i (1..$width){
				my ($r,$g,$b) = splice(@data,0,3);

				if($hig == 1){
					if($r > 10 && $g > 12 && $b > 10){
						$image->Set("pixel[$i,$j]" => 'white');
					}
				}elsif($hig == 2){
					if($r > 10 && $g > 11 && $b > 10){
						$image->Set("pixel[$i,$j]" => 'white');
					}
				}elsif($hig == 3){
					if($r > 11 && $g > 11 && $b > 11){
						$image->Set("pixel[$i,$j]" => 'white');
					}
				}elsif($hig == 4){
					if($r > 12 && $g > 12 && $b > 12){
						$image->Set("pixel[$i,$j]" => 'white');
					}
				}elsif($hig == 5){
					if($r > 15 && $g > 15 && $b > 15){
						$image->Set("pixel[$i,$j]" => 'white');
					}
				}elsif($hig == 6){
					if($r > 8 && $g > 8 && $b > 8){
						$image->Set("pixel[$i,$j]" => 'white');
					}
				}elsif($hig == 7){
					if($r > 9 && $g > 9 && $b > 9){
						$image->Set("pixel[$i,$j]" => 'white');
					}
				}elsif($hig == 8){
					if($r > 7 && $g > 7 && $b > 7){
						$image->Set("pixel[$i,$j]" => 'white');
					}
				}elsif($hig == 9){
					if($r > 20 && $g > 20 && $b > 20){
						$image->Set("pixel[$i,$j]" => 'white');
					}
				}elsif($hig == 10){
					if($r > 25 && $g > 25 && $b > 25){
						$image->Set("pixel[$i,$j]" => 'white');
					}
				}else{
					if($r > 10 && $g > 10 && $b > 10){
						$image->Set("pixel[$i,$j]" => 'white');
					}
				}
			}
		}

		my ($blob2) = $image->ImageToBlob(magick=>'RGB', colorspace=>'RGB', depth=>'8');
		my @data2 = unpack("C*",$blob2);

		for my $j (1..$height){
			for my $i (1..$width){
				my ($r,$g,$b) = splice(@data2,0,3);

				if($r < 245 && $g < 245 && $b < 245){
					$image->Set("pixel[$i,$j]" => 'black');
				}
			}
		}

		for (my $i = 1; $i < ($width-1); $i++) {
			for (my $j = 1; $j < ($height-1); $j++) {

				unless (is_pixel_white $image->Get("pixel[$i,$j]")) {
					my $i2 = $i + 1;
					my $i3 = $i - 1;
					my $j2 = $j + 1;
					my $j3 = $j - 1;

					if ((is_pixel_white $image->Get("pixel[$i2,$j]")) and
							(is_pixel_white $image->Get("pixel[$i3,$j]")) and
							(is_pixel_white $image->Get("pixel[$i2,$j2]")) and
							(is_pixel_white $image->Get("pixel[$i3,$j2]")) and
							(is_pixel_white $image->Get("pixel[$i2,$j3]")) and
							(is_pixel_white $image->Get("pixel[$i3,$j3]")) and
							(is_pixel_white $image->Get("pixel[$i,$j2]")) and
							(is_pixel_white $image->Get("pixel[$i,$j3]"))) {
						$image->Set("pixel[$i,$j]" => 'white');
					}
				}
			}
		}
		$image->Resize(width=>$width*1.7,height=>$height*1.7);
		$image->Gamma(gamma=>0.89,channel=>'RGB');
		$image->Write(filename => "$mynewfile", compression => 'None');

		my $backdata = &command("$tesseract $mynewfile outputbase nobatch digits");
		open(F,"<outputbase.txt");
		my $captchadata2 = join("",<F>);
		close(F);
		unlink("outputbase.txt");
		$captchadata2 =~ s/[^\d]//g;
		$captchadata2 =~ s/000/00/;
		$captchadata2 =~ s/111/11/;
		$captchadata2 =~ s/222/22/;
		$captchadata2 =~ s/333/33/;
		$captchadata2 =~ s/444/44/;
		$captchadata2 =~ s/555/55/;
		$captchadata2 =~ s/666/66/;
		$captchadata2 =~ s/777/77/;
		$captchadata2 =~ s/888/88/;
		$captchadata2 =~ s/999/99/;
		if($captchadata2 =~ /^\d\d\d\d\d\d\d\d$/){
			$captchadata2 =~ s/^\d//;
		}
		if($captchadata2 =~ /^\d\d\d\d\d\d\d$/){
			$captchadata2 =~ s/^\d//;
		}
		if($captchadata2 =~ /^\d\d\d\d\d\d$/){
			$topcap{$captchadata2}++;
		}else{
			$topcap{$captchadata2}++;
		}
	}
	foreach (sort {$topcap{$b} <=> $topcap{$a}} keys %topcap){
		return $_;
	}
}

=pod

=head1 NAME

Finance::Bank::DE::NetBank::Check - Bankaccount details

=head1 SYNOPSIS

	use Finance::Bank::DE::NetBank::Check;
	# only first bankaccount
	my($newdata,$other) = netbankcsv('0000000','000000','./Tesseract-OCR/tesseract');#kto, pin, tesseract for captcha

	foreach my $key (keys %$other){# gesamtsaldo, iban, bic, owner, number, institute, lastlogin
		print $key . ": " . ${$other}{$key} . "\n";
	}

	print "\nDetails:\n";

	foreach my $key (@{$newdata}){
		#foreach my $key2 (keys %{$key}){#buchungstag, wertstellungstag, verwendungszweck, umsatz, waehrung
		#	print ${$key}{$key2};
		#	print "\t";
		#}

		print ${$key}{buchungstag};
		print "\n";
		print ${$key}{wertstellungstag};
		print "\n";
		print ${$key}{verwendungszweck};
		print "\n";
		print ${$key}{umsatz};
		print "\n";
		print ${$key}{waehrung};
		print "\n";
	}

=head1 DESCRIPTION

Finance::Bank::DE::NetBank::Check - Bankaccount details

=head1 AUTHOR

    Stefan Gipper <stefanos@cpan.org>, http://www.coder-world.de/

=head1 COPYRIGHT

	Finance::Bank::DE::NetBank::Check is Copyright (c) 2012 Stefan Gipper
	All rights reserved.

	This program is free software; you can redistribute
	it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO



=cut
