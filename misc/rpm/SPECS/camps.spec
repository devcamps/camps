# Is this package for local-perl or just perl?
%define perl_package local-perl
# Where will the bulk of the camp system reside?
%define camp_root /home/camp
# What goes into camp_root?
%define camp_root_glob_list bin lib htdocs mysql pgsql schema cgi-bin LICENSE README

Name: camps
Summary: Development Camps System
Vendor: End Point Corporation
Packager: Adam Vollrath <adam@endpoint.com>
Version: 3.0
Release: 1
License: GPL and Copyright 2006-2009 End Point Corporation
Group: Development/Tools
URL: http://www.devcamps.org/

Source: camps.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} --name)

BuildRequires: git

Requires: %{perl_package} %{perl_package}(Yaml::Syck)
Requires: %{perl_package}(File::pushd) %{perl_package}(DBI)

%description
DevCamps are a software system and conventions for making automated development
and staging environments called "camps".
Focused on web applications, camps make it easy to keep development
environments up to date, use version control (including in production if 
desired), and coordinate multiple simultaneous projects and developers.

%prep
rm -rf %{buildroot}
git clone http://git.devcamps.org/camps.git %{buildroot}/camps-%{version}

%build
# no-op

%install
cd %{buildroot}/camps-%{version}
mkdir --parents %{buildroot}/%{camp_root}/
for glob in %{camp_root_glob_list}; do
	mv --verbose $glob %{buildroot}/%{camp_root}/
done 
rm -rf %{buildroot}/camps-%{version}

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root)
%{camp_root}
%exclude %{camp_root}/lib/Camp/t
%doc %{camp_root}/LICENSE
%doc %{camp_root}/README

%pre
# Do not install if camps already exists and is not provided by an RPM.
if ([-e %{camp_root} ] && !(rpm -q --whatprovides %{camp_root} >/dev/null)); then
	exit 1
else
	exit 0
fi

%changelog
* Sat Jun 27 2009 Adam Vollrath <adam@endpoint.com>
- Initial build
