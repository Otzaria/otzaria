
<!-- PROJECT SHIELDS -->
<!--
*** I'm using markdown "reference style" links for readability.
*** Reference links are enclosed in brackets [ ] instead of parentheses ( ).
*** See the bottom of this document for the declaration of the reference variables
*** for contributors-url, forks-url, etc. This is an optional, concise syntax you may use.
*** https://www.markdownguide.org/basic-syntax/#reference-style-links
-->
![Downloads][Github-downloads]
[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![GPL-3.0 License][license-shield]][license-url]





<!-- PROJECT LOGO -->
<br />
<div align="center">
  <a href="https://github.com/sivan22/otzaria">
    <img src="images/logo.svg" alt="Logo" width="80" height="80">
  </a>

  <h3 align="center">Otzaria</h3>

  <p align="center">
    Making the jewish library accessible to everyone by creating an app with a modern UI/UX that could run on any device
    <br />
    <a href="https://sivan22.github.io/otzaria-download/"><strong>See our site »</strong></a>
    <br />
    <br/>  
    <a href="https://github.com/sivan22/otzaria/issues/new?labels=bug&template=bug-report---.md">Report a Bug</a>
    ·
    <a href="https://github.com/sivan22/otzaria/issues/new?labels=enhancement&template=feature-request---.md">Request A Feature</a>
    ·
    <a href="https://github.com/sivan22/otzaria/wiki">User manual</a>
  </p>
</div>



<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#built-with">Built With</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>



<!-- ABOUT THE PROJECT -->
## About The Project

![alt text](image.png)

I felt the lack of an open source app of the jewish library, for PCs.


Torat Emet is old and no longer maintained, and Sefaria's app is great, however, it does not work well on computers.

So I decided to make one myself. I did not know Dart and Flutter at all in the beginning, but it was fun. I **love** to learn new technologies!

The database itself is accessible to everyone following the important work of the Sefaria organization, so a big thank to them for that.

Key features of the project:
* The software is FREE and will remain ALWAYS FREE.
* Built to work effeciently on any device, including Windows, Linux, and Android.
* The app is designed to be as user friendly as possible.
* A thorough selection process has been undertaken to ensure that the books are suitable for the Torah community
* The library is flexible, means that you can add or remove books from the library.
* Fast search engine, including user-added books.
* The app supports the following formats: TXT, Docx and PDF.

I hope that my work will help the Torah community to learn easily and effectively anytime and anywhere.

<p align="right">(<a href="#readme-top">&#8679;</a>)</p>


### Built With



* [![Dart][dart]][Dart-url]
* [![Flutter][Flutter]][Flutter-url]

I Chose to use Dart and Flutter. I think that is the most efficient and most modern way to build a GUI app.

Also, it is a multiplatform framework.

<p align="right">(<a href="#readme-top">&#8679;</a>)</p>


<!-- GETTING STARTED -->
## Getting Started

### windows
#### Installation

**Choose your installer:**

1. **Full Installer (Recommended)** - `otzaria-x.x.x-windows-full.exe`
   - Includes all required dependencies (Visual C++ Redistributable)
   - Automatically installs missing components
   - Best choice for most users
   - Larger download size (~100MB more)

2. **Regular Installer** - `otzaria-x.x.x-windows.exe`
   - Smaller download size
   - Requires Visual C++ Redistributable to be pre-installed
   - For users who know they already have the required dependencies

Download the latest build for Windows from [releases](https://github.com/Sivan22/otzaria/releases). 

**Note:** The library is included in the .exe file.
In case you need only the app itself for upgrading, download the Windows ZIP build from releases.

#### Prerequisites (for Regular Installer only)
If using the regular installer, make sure that Visual C++ Redistributable is installed on your computer. If not, download it from [here](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170) and install it.

### linux
#### Prerequisites
```sudo apt-get install libgtk-3-0 libblkid1 liblzma5```
#### Installation
* Download the linux build from releases, extract and run Otzaria.
* For version releases there is also a FULL bundle: `otzaria-linux-full.tar.gz`.
* The FULL bundle includes the app and the library together. Extract it and run `run-otzaria.sh`.
* When first running the app, you will be asked to download the library.
* Llternatively, you can download the library manually from [here](https://github.com/Sivan22/otzaria-library/releases), extract it and provide its path to the app.

### android
* The app is available on Google Play: [link](https://play.google.com/store/apps/details?id=com.mendelg.otzaria&pli=1)
* Alternatively, you can download the .apk file from the releases page, and install it.
* For version releases there is also a FULL bundle: `otzaria-android-full.zip`.
* The Android FULL bundle includes the APK together with the offline library payload for distribution.
* When first running the app, you will be asked to download the library.
* Alternatively, you can download the library manually from [here](https://github.com/Sivan22/otzaria-library/releases) and provide the zip file to the app.

### iOS (iPhone/iPad)
* The app is available on AppStore: [link](https://apps.apple.com/us/app/otzaria/id6738098031)
* When first running the app, you will be asked to download the library.

### macos
* Download the latest MacOS build from the releases page.
* For version releases there is also a FULL bundle: `otzaria-macos-full.zip`.
* The FULL bundle includes the app and the library together. Extract it and launch `Run Otzaria.command`.
* Run the app while pressing the ctrl key.
* When first running the app, you will be asked to download the library.
* Alternatively, you can download the library manually from [here](https://github.com/Sivan22/otzaria-library/releases), extract it and provide its path to the app.



<p align="right">(<a href="#readme-top">&#8679;</a>)</p>


<!-- USAGE EXAMPLES -->
## Usage

See the Wiki section for documentation.

<p align="right">(<a href="#readme-top">&#8679;</a>)</p>


<!-- ROADMAP -->
## Roadmap

- [ ] Add business logic layer by switching the state management library to Bloc.
- [ ] Transfer books data from text files to SQLite database
- [ ] Add option for semantic search using an embedding ML model and vector database
- [ ] Language Support
    - [ ] English
    - [X] Hebrew

See the [open issues](https://github.com/sivan22/otzaria/issues) for a full list of proposed features (and known issues).

<p align="right">(<a href="#readme-top">&#8679;</a>)</p>


<!-- CONTRIBUTING -->
## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".
Don't forget to give the project a star! Thanks again!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Build Troubleshooting

**SSL Certificate Error on Filtered Networks (NetFree, etc.)**

If you encounter an SSL certificate error when building for Windows (e.g., `status_code: 60`, `CERT_TRUST_REVOCATION_STATUS_UNKNOWN`), it is likely due to network filtering.

For a detailed step-by-step solution, please refer to the **[NetFree Wiki - Flutter Setup Guide](https://netfree.link/wiki/%D7%94%D7%AA%D7%A7%D7%A0%D7%AA_%D7%AA%D7%A2%D7%95%D7%93%D7%94_%D7%A2%D7%91%D7%95%D7%A8_%D7%A1%D7%91%D7%99%D7%91%D7%AA_Flutter#windows)**.

**Quick Fix (PowerShell):**
If you need a quick workaround before building, run:
```powershell
$env:CMAKE_TLS_VERIFY="0"
flutter build windows
```

<p align="right">(<a href="#readme-top">&#8679;</a>)</p>


<!-- LICENSE -->
## License

The code is licensed under the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html).

This means:
- ✅ You can use, modify, and distribute this software
- ✅ Any modifications must be released under the same GPL-3.0 license
- ✅ Source code must be made available when distributing
- ❌ Commercial use requires sharing all modifications and improvements

The texts have different open licenses. You may check Sefaria's site for more info on that.

<p align="right">(<a href="#readme-top">&#8679;</a>)</p>


<!-- CONTACT -->
## Contact

Sivan Ratson-  - sivan.ratson@gmail.com

Project Link: [https://github.com/sivan22/otzaria](https://github.com/sivan22/otzaria)

<p align="right">(<a href="#readme-top">&#8679;</a>)</p>


<!-- ACKNOWLEDGMENTS -->
## Acknowledgments

תוכנה זו נוצרה והוקדשה על ידי: [sivan22](https://github.com/Sivan22), [Y.PL.](https://github.com/Y-PLONI), [YOSEFTT](https://github.com/YOSEFTT), [zevisvei](https://github.com/zevisvei), [NHLOCAL (פיתוח "זכור ושמור")](https://github.com/NHLOCAL/Shamor-Zachor), [evel-avalim (פיתוח הגימטריות)](https://github.com/evel-avalim).
<br>
<br>


The project was possible because of Sefaria's amazing project. 
<br>
and Dicta association, by which many important books were added.
<br>
<br>
<a href="https://www.sefaria.org/texts" title="ספריא" target="_blank"><img src="images/safria logo.png" alt="ספריא" width="154" height="80"/></a>
<a href="https://github.com/Dicta-Israel-Center-for-Text-Analysis/Dicta-Library-Download" title="דיקטה" target="_blank"><img src="images/dicta_logo.jpg" alt="דיקטה" width="154" height="80"/></a>
<a href="https://github.com/MosheWagner/Orayta-Books" title="אורייתא" target="_blank"><img src="images/Orayta.png" alt="אורייתא" width="200" height="80"/></a>
<a href="http://mobile.tora.ws" title="ובלכתך בדרך" target="_blank"><img src="images/OnYourWay_logo.jpg" alt="ובלכתך בדרך" width="80" height="80"/></a>
<a href="http://www.toratemetfreeware.com/index.html?downloads;1;" title="תורת אמת" target="_blank"><img src="images/toratemet.png" alt="תורת אמת" width="80" height="80"/></a>
<a href="https://wiki.jewishbooks.org.il/mediawiki/wiki/%D7%A2%D7%9E%D7%95%D7%93_%D7%A8%D7%90%D7%A9%D7%99" title="אוצר הספרים היהודי" target="_blank"><img src="images/JewishBook-logo-שקוף.png" alt="אוצר הספרים היהודי" width="200" height="80"/></a>
<a href="https://he.wikisource.org/wiki" title="ויקיטקסט" target="_blank"><img src="images/wikisource.jpg" alt="ויקיטקסט" width="80" height="80"/></a>
<a href="https://pninim.org/" title="פנינים" target="_blank"><img src="images/pninim.png" alt="פנינים" width="200" height="80"/></a>

<!--a href="https://github.com/projectbenyehuda/public_domain_dump" title="פרוייקט בן יהודה" target="_blank"><img src="images/Project Ben-Yehuda logo.jpg" alt="פרוייקט בן יהודה" width="80" height="80"/></a -->

The PDF viewer is powered by [pdfrx](https://pub.dev/packages/pdfrx).

For automatic updates, I used [updat](https://pub.dev/packages/updat).

<p align="right">(<a href="#readme-top">&#8679;</a>)</p>


<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->
[contributors-shield]: https://img.shields.io/github/contributors/sivan22/otzaria.svg?style=for-the-badge
[contributors-url]: https://github.com/sivan22/otzaria/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/sivan22/otzaria.svg?style=for-the-badge
[forks-url]: https://github.com/sivan22/otzaria/network/members
[stars-shield]: https://img.shields.io/github/stars/sivan22/otzaria.svg?style=for-the-badge
[stars-url]: https://github.com/sivan22/otzaria/stargazers
[issues-shield]: https://img.shields.io/github/issues/sivan22/otzaria.svg?style=for-the-badge
[issues-url]: https://github.com/sivan22/otzaria/issues
[Github-downloads]: https://img.shields.io/github/downloads/sivan22/otzaria/total.svg?style=for-the-badge
[license-shield]: https://img.shields.io/github/license/sivan22/otzaria.svg?style=for-the-badge
[license-url]: https://github.com/sivan22/otzaria/blob/master/LICENSE.txt
[linkedin-shield]: https://img.shields.io/badge/-LinkedIn-black.svg?style=for-the-badge&logo=linkedin&colorB=555
[linkedin-url]: https://linkedin.com/in/othneildrew
[product-screenshot]: images/screenshot.png
[dart]: https://img.shields.io/badge/dart-000000?style=for-the-badge&logo=dart&logoColor=61DAFB
[Dart-url]: https://dart.dev/
[Flutter]: https://img.shields.io/badge/Flutter-20232A?style=for-the-badge&logo=flutter&logoColor=61DAFB
[Flutter-url]: https://flutter.dev/
[Vue.js]: https://img.shields.io/badge/Vue.js-35495E?style=for-the-badge&logo=vuedotjs&logoColor=4FC08D
[Vue-url]: https://vuejs.org/
[Angular.io]: https://img.shields.io/badge/Angular-DD0031?style=for-the-badge&logo=angular&logoColor=white
[Angular-url]: https://angular.io/
[Svelte.dev]: https://img.shields.io/badge/Svelte-4A4A55?style=for-the-badge&logo=svelte&logoColor=FF3E00
[Svelte-url]: https://svelte.dev/
[Laravel.com]: https://img.shields.io/badge/Laravel-FF2D20?style=for-the-badge&logo=laravel&logoColor=white
[Laravel-url]: https://laravel.com
[Bootstrap.com]: https://img.shields.io/badge/Bootstrap-563D7C?style=for-the-badge&logo=bootstrap&logoColor=white
[Bootstrap-url]: https://getbootstrap.com
[JQuery.com]: https://img.shields.io/badge/jQuery-0769AD?style=for-the-badge&logo=jquery&logoColor=white
[JQuery-url]: https://jquery.com
