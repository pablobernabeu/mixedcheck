# FSF entries on GPL compatibility

**Pages read, 21 November 2026, in the browser.**
- Free Software Foundation, *Frequently asked questions about the GNU licenses*, entry #IfLibraryIsGPL, https://www.gnu.org/licenses/gpl-faq.html#IfLibraryIsGPL (page dated 13 January 2026).
- Free Software Foundation, *Various licenses and comments about them*, entry #Expat, https://www.gnu.org/licenses/license-list.html#Expat (page dated 22 April 2026).

**Fact.**
- #IfLibraryIsGPL: when a library is released under the GPL (not the LGPL), software that links to it forms a combination to which the GPL applies as a whole. The modules that link to the library may carry other GPL-compatible licences, but the combined work must be licensed under the GPL.
- #Expat: the Expat licence is a lax, permissive, non-copyleft free software licence, compatible with the GNU GPL. The FSF notes that it is often called 'the MIT License', a name it advises against because MIT has used several licences, among them the X11 licence, which differs by a paragraph on the X Consortium's name.

**Bearing on 02-decisions.md (Q10).** Q10 says that the FSF lists the Expat (MIT) licence as GPL-compatible, 'to be confirmed on gnu.org'; the licence list confirms it. The FAQ entry supports the decision's reading: an MIT-licensed package may use GPL-family dependencies, since MIT is GPL-compatible, and the GPL governs a combined work that is distributed. That remains consistent with Q10's rule that no code is copied or translated from GPL or AGPL packages, which keeps the packages' own code MIT. The words 'to be confirmed on gnu.org' can be removed.

**Questions for a person.** None.
