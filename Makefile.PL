use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Finance::Bank::DE::NetBank::Check',
    'VERSION_FROM'	=> 'Check.pm', # finds $VERSION
    'PREREQ_PM'		=> {WWW::Mechanize => 1.00,File::Temp => 0.10,Image::Magick => 1.00},
    ($] >= 5.005 ? (
      ABSTRACT_FROM => 'Check.pm', 
      AUTHOR     => 'Stefan Gipper <stefanos@cpan.org>',
    ) : ()),
);
