import Foundation

public enum ArchitectureRenderer {
    private static let base64HTMLTemplate = """
PCFET0NUWVBFIGh0bWw+CjxodG1sIGxhbmc9ImtvIiBkYXRhLXRoZW1lPSJkYXJrIj4KPGhlYWQ+
PG1ldGEgY2hhcnNldD0iVVRGLTgiPgo8bWV0YSBuYW1lPSJ2aWV3cG9ydCIgY29udGVudD0id2lk
dGg9ZGV2aWNlLXdpZHRoLCBpbml0aWFsLXNjYWxlPTEuMCI+Cjx0aXRsZT5fX1RJVExFX188L3Rp
dGxlPgo8c3R5bGU+CiAgOnJvb3QgewogICAgLS1iZzogIzBkMTExNzsgLS1zdXJmYWNlOiAjMTYx
YjIyOyAtLWJvcmRlcjogIzMwMzZzZDsgLS10ZXh0OiAjYzlkMWQ5OyAtLXRleHQtYnJpZ2h0OiAj
ZjBmNmZjOwogICAgLS1wcmltYXJ5OiAjMmY4MWY3OyAtLWFjY2VudC1raXQ6ICMyMzg2MzY7IC0t
YWNjZW50LWFwcDogI2EzNzFmNzsgLS1kaW1tZWQ6IDAuMTU7CiAgfQogIFtkYXRhLXRoZW1lPSJs
aWdodCJdIHsKICAgIC0tYmc6ICNmNmY4ZmE7IC0tc3VyZmFjZTogI2ZmZmZmZjsgLS1ib3JkZXI6
ICNkMGQ3ZGU7IC0tdGV4dDogIzI0MjkyZjsgLS10ZXh0LWJyaWdodDogIzFmMjMyODsKICAgIC0t
cHJpbWFyeTogIzA5NjlkYTsgLS1hY2NlbnQta2l0OiAjMWE3ZjM3OyAtLWFjY2VudC1hcHA6ICM4
MjUwZGY7IC0tZGltbWVkOiAwLjE1OwogIH0KICAqIHsgYm94LXNpemluZzogYm9yZGVyLWJveDsg
bWFyZ2luOiAwOyBwYWRkaW5nOiAwOyBmb250LWZhbWlseTogLWFwcGxlLXN5c3RlbSwgQmxpbmtN
YWNTeXN0ZW1Gb250LCAiU0YgUHJvIiwgc2Fucy1zZXJpZjsgfQogIGJvZHkgeyBiYWNrZ3JvdW5k
OiB2YXIoLS1iZyk7IGNvbG9yOiB2YXIoLS10ZXh0KTsgb3ZlcmZsb3c6IGhpZGRlbjsgd2lkdGg6
IDEwMHZ3OyBoZWlnaHQ6IDEwMHZoOyB9CiAgaGVhZGVyIHsgcG9zaXRpb246IGFic29sdXRlOyB0
b3A6IDE2cHg7IGxlZnQ6IDE2cHg7IHotaW5kZXg6IDEwOyBiYWNrZ3JvdW5kOiB2YXIoLS1zdXJm
YWNlKTsgYm9yZGVyOiAxcHggc29saWQgdmFyKC0tYm9yZGVyKTsgcGFkZGluZzogOHB4IDE2cHg7
IGJvcmRlci1yYWRpdXM6IDhweDsgZGlzcGxheTogZmxleDsgZ2FwOiAxMnB4OyBhbGlnbi1pdGVt
czogY2VudGVyOyB9CiAgaDEgeyBmb250LXNpemU6IDE1cHg7IGNvbG9yOiB2YXIoLS10ZXh0LWJy
aWdodCk7IH0KICAuYmFkZ2UgeyBmb250LXNpemU6IDExcHg7IGJhY2tncm91bmQ6IHZhcigtLWJv
cmRlcik7IHBhZGRpbmc6IDJweCA2cHg7IGJvcmRlci1yYWRpdXM6IDRweDsgfQogIC5kb2NrIHsg
cG9zaXRpb246IGFic29sdXRlOyBib3R0b206IDE2cHg7IGxlZnQ6IDE2cHg7IHotaW5kZXg6IDEw
OyBkaXNwbGF5OiBmbGV4OyBnYXA6IDhweDsgfQogIC5idG4geyBiYWNrZ3JvdW5kOiB2YXIoLS1z
dXJmYWNlKTsgY29sb3I6IHZhcigtLXRleHQpOyBib3JkZXI6IDFweCBzb2xpZCB2YXIoLS1ib3Jk
ZXIpOyBwYWRkaW5nOiA2cHggMTJweDsgYm9yZGVyLXJhZGl1czogNnB4OyBjdXJzb3I6IHBvaW50
ZXI7IGZvbnQtc2l6ZTogMTJweDsgfQogIC5idG46aG92ZXIgeyBib3JkZXItY29sb3I6IHZhcigt
LXByaW1hcnkpOyB9CiAgI2NhbnZhcy1jb250YWluZXIgeyB3aWR0aDogMTAwdnc7IGhlaWdodDog
MTAwdmg7IGN1cnNvcjogZ3JhYjsgfQogICNjYW52YXMtY29udGFpbmVyOmFjdGl2ZSB7IGN1cnNv
cjogZ3JhYmJpbmc7IH0KICBzdmcgeyB3aWR0aDogMTAwJTstaGVpZ2h0OiAxMDAlOyB9CiAgLm5v
ZGUtYm94IHsgZmlsbDogdmFyKC0tc3VyZmFjZSk7IHN0cm9rZTogdmFyKC0tYm9yZGVyKTsgc3Ry
b2tlLXdpZHRoOiAxLjU7IHJ4OiA4OyBjdXJzb3I6IHBvaW50ZXI7IHRyYW5zaXRpb246IGFsbCAw
LjJzOyB9CiAgLm5vZGUtYm94OmhvdmVyIHsgc3Ryb2tlOiB2YXIoLS1wcmltYXJ5KTsgfQogIC5u
b2RlLWJveC5zZWxlY3RlZCB7IHN0cm9rZTogdmFyKC0tcHJpbWFyeSk7IHN0cm9rZS13aWR0aDog
Mi41OyB9CiAgLm5vZGUtdGl0bGUgeyBmaWxsOiB2YXIoLS10ZXh0LWJyaWdodCk7IGZvbnQtc2l6
ZTogMTJweDsgZm9udC13ZWlnaHQ6IDYwMDsgcG9pbnRlci1ldmVudHM6IG5vbmU7IH0KICAubm9k
ZS1zdWIgeyBmaWxsOiB2YXIoLS10ZXh0KTsgZm9udC1zaXplOiAxMHB4OyBwb2ludGVyLWV2ZW50
czogbm9uZTsgfQogIC5lZGdlIHsgZmlsbDogbm9uZTsgc3Ryb2tlOiB2YXIoLS1ib3JkZXIpOyBz
dHJva2Utd2lkdGg6IDEuNTsgdHJhbnNpdGlvbjogc3Ryb2tlIDAuMnM7IH0KICAuZWRnZS5oaWdo
bGlnaHQgeyBzdHJva2U6IHZhcigtLXByaW1hcnkpOyBzdHJva2Utd2lkdGg6IDIuNTsgfQogIC5k
aW1tZWQgeyBvcGFjaXR5OiB2YXIoLS1kaW1tZWQpICFpbXBvcnRhbnQ7IH0KICAjaW5zcGVjdG9y
IHsgcG9zaXRpb246IGFic29sdXRlOyB0b3A6IDA7IHJpZ2h0OiAwOyB3aWR0aDogMzQwcHg7IGhl
aWdodDogMTAwdmg7IGJhY2tncm91bmQ6IHZhcigtLXN1cmZhY2UpOyBib3JkZXItbGVmdDogMXB4
IHNvbGlkIHZhcigtLWJvcmRlcik7IHBhZGRpbmc6IDIwcHg7IHRyYW5zZm9ybTogdHJhbnNsYXRl
WChEwMCUyk7IHRyYW5zaXRpb246IHRyYW5zZm9ybSAwLjI1czsgei1pbmRleDogMjA7IG92ZXJm
bG93LXk6IGF1dG87IH0KICAjaW5zcGVjdG9yLm9wZW4geyB0cmFuc2Zvcm06IHRyYW5zbGF0ZVgo
MCk7IH0KICAuY2xvc2UtYnRuIHsgYmFja2dyb3VuZDogbm9uZTsgYm9yZGVyOiBub25lOyBmb250
LXNpemU6IDE4cHg7IGNvbG9yOiB2YXIoLS10ZXh0KTsgY3Vyc29yOiBwb2ludGVyOyBmbG9hdDog
cmlnaHQ7IH0KPC9zdHlsZT4KPC9oZWFkPgo8Ym9keT4KPGhlYWRlcj4KICA8aDE+X19USVRMRV9f
PC9oMT4KICA8c3BhbiBjbGFzcz0iYmFkZ2UiPk5vZGVzOiA8c3BhbiBpZD0iY291bnQtbm9kZXMi
Pl9fTk9ERVNfQ09VTlRfXzwvc3Bhbj48L3NwYW4+CiAgPHNwYW4gY2xhc3M9ImJhZGdlIj5FZGdl
czogPHNwYW4gaWQ9ImNvdW50LWVkZ2VzIj5fX0VER0VTX0NPVU5UX188L3NwYW4+PC9zcGFuPgo8
L2hlYWRlcj4KPGRpdiBjbGFzcz0iZG9jayI+CiAgPGJ1dHRvbiBjbGFzcz0iYnRuIiBpZD0iYnRu
LXRoZW1lIj7wn4yTIFRoZW1lPC9idXR0b24+CiAgPGJ1dHRvbiBjbGFzcz0iYnRuIiBpZD0iYnRu
LXJlc2V0Ij7im7YgRml0IFZpZXc8L2J1dHRvbj4KPC9kaXY+CjxkaXYgaWQ9ImNhbnZhcy1jb250
YWluZXIiPgogIDxzdmcgaWQ9InZpZXdwb3J0Ij4KICAgIDxnIGlkPSJ3b3JsZCI+PC9nPgogIDwv
c3ZnPgo8L2Rpdj4KPGFzaWRlIGlkPSJpbnNwZWN0b3IiPgogIDxidXR0b24gY2xhc3M9ImNsb3Nl
LWJ0biIgaWQ9ImJ0bi1jbG9zZSI+JnRpbWVzOzwvYnV0dG9uPgogIDxoMiBpZD0iaW5zcC10aXRs
ZSIgc3R5bGU9ImZvbnQtc2l6ZTogMTZweDsgbWFyZ2luLWJvdHRvbTogOHB4OyI+Tm9kZSBUaXRs
ZTwvaDI+CiAgPGRpdiBpZD0iaW5zcC10eXBlIiBjbGFzcz0iYmFkZ2UiIHN0eWxlPSJtYXJnaW4t
Ym90dG9tOiAxMnB4OyI+VHlwZTwvZGl2PgogIDxwIGlkPSJpbnNwLWV2aWRlbmNlIiBzdHlsZT0i
Zm9udC1zaXplOiAxMnB4OyBjb2xvcjogdmFyKC0tdGV4dCk7IG1hcmdpbi1ib3R0b206IDE2cHg7
Ij48L3A+CiAgPGgzIHN0eWxlPSJmb250LXNpemU6IDEzcHg7IG1hcmdpbi1ib3R0b206IDhweDsi
PkRlcGVuZGVuY2llczwvaDM+CiAgPHVsIGlkPSJpbnNwLWRlcHMiIHN0eWxlPSJmb250LXNpemU6
IDEycHg7IGxpc3Qtc3R5bGU6IG5vbmU7IGRpc3BsYXk6IGZsZXg7IGZsZXgtZGlyZWN0aW9uOiBj
b2x1bW47IGdhcDogNHB4OyI+PC91bD4KPC9hc2lkZT4KCjxzY3JpcHQgaWQ9ImlyLWRhdGEiIHR5
cGU9ImFwcGxpY2F0aW9uL2pzb24iPgpfX0pTT05fREFUQV9fCjwvc2NyaXB0Pgo8c2NyaXB0Pgoo
KCkgPT4gewogIGNvbnN0IGRhdGEgPSBKU09OLnBhcnNlKGRvY3VtZW50LmdldEVsZW1lbnRCeUlk
KCdpci1kYXRhJykudGV4dENvbnRlbnQpOwogIGNvbnN0IHdvcmxkID0gZG9jdW1lbnQuZ2V0RWxl
bWVudEJ5SWQoJ3dvcmxkJyk7CiAgY29uc3QgY29udGFpbmVyID0gZG9jdW1lbnQuZ2V0RWxlbWVu
dEJ5SWQoJ2NhbnZhcy1jb250YWluZXInKTsKICBjb25zdCBpbnNwZWN0b3IgPSBkb2N1bWVudC5n
ZXRFbGVtZW50QnlJZCgnaW5zcGVjdG9yJyk7CiAgCiAgbGV0IHNjYWxlID0gMC42LCB0eCA9IDgw
LCB0eSA9IDgwOwogIGxldCBpc0RyYWdnaW5nID0gZmFsc2UsIHN0YXJ0WCA9IDAsIHN0YXJ0WSA9
IDA7CiAgCiAgZnVuY3Rpb24gdXBkYXRlVHJhbnNmb3JtKCkgewogICAgd29ybGQuc2V0QXR0cmli
dXRlKCd0cmFuc2Zvcm0nLCAnbWF0cml4KCcgKyBzY2FsZSArICcgMCAwICcgKyBzY2FsZSArICcg
JyArIHR4ICsgJyAnICsgdHkgKyAnKScpOwogIH0KICB1cGRhdGVUcmFuc2Zvcm0oKTsKCiAgY29u
dGFpbmVyLmFkZEV2ZW50TGlzdGVuZXIoJ21vdXNlZG93bicsIChlKSA9PiB7CiAgICBpZiAoZS50
YXJnZXQuY2xvc2VzdCgnLm5vZGUtZycpKSByZXR1cm47CiAgICBpc0RyYWdnaW5nID0gdHJ1ZTsK
ICAgIHN0YXJ0WCA9IGUuY2xpZW50WCAtIHR4OwogICAgc3RhcnRZID0gZS5jbGllbnRZIC0gdHk7
CiAgfSk7CiAgd2luZG93LmFkZEV2ZW50TGlzdGVuZXIoJ21vdXNlbW92ZScsIChlKSA9PiB7CiAg
ICBpZiAoIWlzRHJhZ2dpbmcpIHJldHVybjsKICAgIHR4ID0gZS5jbGllbnRYIC0gc3RhcnRYOwog
ICAgdHkgPSBlLmNsaWVudFkgLSBzdGFydFk7CiAgICB1cGRhdGVUcmFuc2Zvcm0oKTsKICB9KTsK
ICB3aW5kb3cuYWRkRXZlbnRMaXN0ZW5lcignbW91c2V1cCcsICgpID0+IHsgaXNEcmFnZ2luZyA9
IGZhbHNlOyB9KTsKICBjb250YWluZXIuYWRkRXZlbnRMaXN0ZW5lcignd2hlZWwnLCAoZSkgPT4g
ewogICAgZS5wcmV2ZW50RGVmYXVsdCgpOwogICAgY29uc3QgZmFjdG9yID0gZS5kZWx0YVkgPCAw
ID8gMS4wOCA6IDAuOTI7CiAgICBzY2FsZSA9IE1hdGgubWluKE1hdGgubWF4KDAuMSwgc2NhbGUg
KiBmYWN0b3IpLCAzLjApOwogICAgdXBkYXRlVHJhbnNmb3JtKCk7CiAgfSwgeyBwYXNzaXZlOiBm
YWxzZSB9KTsKCiAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2J0bi10aGVtZScpLm9uY2xpY2sg
PSAoKSA9PiB7CiAgICBjb25zdCByb290ID0gZG9jdW1lbnQuZG9jdW1lbnRFbGVtZW50OwogICAg
Y29uc3QgaXNEYXJrID0gcm9vdC5nZXRBdHRyaWJ1dGUoJ2RhdGEtdGhlbWUnKSA9PT0gJ2Rhcmsn
OwogICAgcm9vdC5zZXRBdHRyaWJ1dGUoJ2RhdGEtdGhlbWUnLCBpc0RhcmsgPyAnbGlnaHQnIDog
J2RhcmsnKTsKICB9OwogIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdidG4tcmVzZXQnKS5vbmNs
aWNrID0gKCkgPT4geyBzY2FsZSA9IDAuNjsgdHggPSA4MDsgdHkgPSA4MDsgdXBkYXRlVHJhbnNm
b3JtKCk7IH07CiAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2J0bi1jbG9zZScpLm9uY2xpY2sg
PSAoKSA9PiB7IGluc3BlY3Rvci5jbGFzc0xpc3QucmVtb3ZlKCdvcGVuJyk7IH07CgogIC8vIEdy
aWQgTGF5b3V0CiAgY29uc3Qgbm9kZU1hcCA9IG5ldyBNYXAoKTsKICBjb25zdCBjb2xzID0gMTI7
CiAgY29uc3QgY29sV2lkdGggPSAyMjAsIHJvd0hlaWdodCA9IDkwOwogIGRhdGEubm9kZXMuZm9y
RWFjaCgobiwgaWR4KSA9PiB7CiAgICBjb25zdCByID0gTWF0aC5mbG9vcihpZHggLyBjb2xzKTsK
ICAgIGNvbnN0IGMgPSBpZHggJSBjb2xzOwogICAgbm9kZU1hcC5zZXQobi5pZCwgT2JqZWN0LmFz
c2lnbih7fSwgbiwgeyB4OiBjICogY29sV2lkdGgsIHk6IHIgKiByb3dIZWlnaHQgfSkpOwogIH0p
OwoKICAvLyBSZW5kZXIgRWRnZXMKICBsZXQgZWRnZXNIdG1sID0gJyc7CiAgZGF0YS5lZGdlcy5m
b3JFYWNoKGUgPT4gewogICAgY29uc3QgcyA9IG5vZGVNYXAuZ2V0KGUuc291cmNlKTsKICAgIGNv
bnN0IHQgPSBub2RlTWFwLmdldChlLnRhcmdldCk7CiAgICBpZiAoIXMgfHwgIXQpIHJldHVybjsK
ICAgIGNvbnN0IHN4ID0gcy54ICsgOTAsIHN5ID0gcy55ICsgNTA7CiAgICBjb25zdCB0eCA9IHQue
SArIDkwLCB0eSA9IHQueSArIDEwOwogICAgZWRnZXNIdG1sICs9ICc8cGF0aCBjbGFzcz0iZWRn
ZSIgaWQ9ImVkZ2UtJyArIGUuc291cmNlICsgJy0nICsgZS50YXJnZXQgKyAnIiBkYXRhLXNvdXJj
ZT0iJyArIGUuc291cmNlICsgJyIgZGF0YS10YXJnZXQ9IicgKyBlLnRhcmdldCArICciIGQ9Ik0g
JyArIHN4ICsgJyAnICsgc3kgKyAnIEMgJyArIHN4ICsgJyAnICsgKChzeSt0eSkvMikgKyAnLCAn
ICsgdHggKyAnICcgKyAoKHN5K3R5KS8yKSArICcsICcgKyB0eCArICcgJyArIHR5ICsgJyIgLz4n
OwogIH0pOwoKICAvLyBSZW5kZXIgTm9kZXMKICBsZXQgbm9kZXNIdG1sID0gJyc7CiAgZGF0YS5u
b2Rlcy5mb3JFYWNoKG4gPT4gewogICAgY29uc3QgcCA9IG5vZGVNYXAuZ2V0KG4uaWQpOwogICAg
Y29uc3QgaXNLaXQgPSBuLnR5cGUgPT09ICdzd2lmdGtpdCc7CiAgICBjb25zdCBzdHJva2VDb2xv
ciA9IGlzS2l0ID8gJ3ZhcigtLWFjY2VudC1raXQpJyA6ICd2YXIoLS1hY2NlbnQtYXBwKSc7CiAg
ICBub2Rlc0h0bWwgKz0gJzxnIGNsYXNzPSJub2RlLWciIGRhdGEtaWQ9IicgKyBuLmlkICsgJyIg
dHJhbnNmb3JtPSJ0cmFuc2xhdGUoJyArIHAueCArICcsICcgKyBwLnkgKyAnKSI+JyArCiAgICAg
ICc8cmVjdCBjbGFzcz0ibm9kZS1ib3giIHdpZHRoPSIxODAiIGhlaWdodD0iNjAiIHN0eWxlPSJi
b3JkZXItY29sb3I6ICcgKyBzdHJva2VDb2xvciArICc7IiAvPicgKwogICAgICAnPHRleHQgY2xh
c3M9Im5vZGUtdGl0bGUiIHg9IjEyIiB5PSIyNCI+JyArIG4ubmFtZSArICc8L3RleHQ+JyArCiAg
ICAgICc8dGV4dCBjbGFzcz0ibm9kZS1zdWIiIHg9IjEyIiB5PSI0NCI+JyArIG4udHlwZSArICc8
L3RleHQ+JyArCiAgICAnPC9nPic7CiAgfSk7CgogIHdvcmxkLmlubmVySFRNTCA9ICc8ZyBpZD0i
ZWRnZXMtbGF5ZXIiPicgKyBlZGdlc0h0bWwgKyAnPC9nPjxnIGlkPSJub2Rlcy1sYXllciI+JyAr
IG5vZGVzSHRtbCArICc8L2c+JzsKCiAgLy8gU2VsZWN0IE5vZGUKICBkb2N1bWVudC5xdWVyeVNl
bGVjdG9yQWxsKCcubm9kZS1nJykuZm9yRWFjaChlbCA9PiB7CiAgICBlbC5hZGRFdmVudExpc3Rl
bmVyKCdjbGljaycsIChlKSA9PiB7CiAgICAgIGUuc3RvcFByb3BhZ2F0aW9uKCk7CiAgICAgIGNv
bnN0IGlkID0gZWwuZ2V0QXR0cmlidXRlKCdkYXRhLWlkJyk7CiAgICAgIGNvbnN0IG4gPSBub2Rl
TWFwLmdldChpZCk7CiAgICAgIGlmICghbikgcmV0dXJuOwoKICAgICAgZG9jdW1lbnQucXVlcnlT
ZWxlY3RvckFsbCgnLm5vZGUtYm94JykuZm9yRWFjaChiID0+IGIuY2xhc3NMaXN0LnJlbW92ZSgn
c2VsZWN0ZWQnKSk7CiAgICAgIGVsLnF1ZXJ5U2VsZWN0b3IoJy5ub2RlLWJveCcpLmNsYXNzTGlz
dC5hZGQoJ3NlbGVjdGVkJyk7CgogICAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnaW5zcC10
aXRsZScpLnRleHRDb250ZW50ID0gbi5uYW1lOwogICAgICBkb2N1bWVudC5nZXRFbGVtZW50QnlJ
ZCgnaW5zcC10eXBlJykudGV4dENvbnRlbnQgPSBuLnR5cGUudG9VcHBlckNhc2UoKTsKICAgICAg
ZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ2luc3AtZXZpZGVuY2UnKS50ZXh0Q29udGVudCA9IG4u
c291cmNlRXZpZGVuY2U/LmZpbGVQYXRoIHx8ICcnOwoKICAgICAgY29uc3QgZGVwcyA9IGRhdGEu
ZWRnZXMuZmlsdGVyKGVkID0+IGVkLnNvdXJjZSA9PT0gaWQpLm1hcChlZCA9PiBlZC50YXJnZXQp
OwogICAgICBjb25zdCB1bCA9IGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdpbnNwLWRlcHMnKTsK
ICAgICAgdWwuaW5uZXJIVE1MID0gZGVwcy5sZW5ndGggPT09IDAgPyAnPGxpPk5vbmU8L2xpPicg
OiBkZXBzLm1hcChkID0+ICc8bGk+4oaSICcgKyAobm9kZU1hcC5nZXQoZCk/Lm5hbWUgfHwgZCkg
KyAnPC9saT4nKS5qb2luKCcnKTsKCiAgICAgIGluc3BlY3Rvci5jbGFzc0xpc3QuYWRkKCdvcGVu
Jyk7CiAgICB9KTsKICB9KTsKfSkoKTsKPC9zY3JpcHQ+CjwvYm9keT4KPC9odG1sPg==
"""

    public static func renderHTML(document: ArchitectureIRDocument, title: String = "swift-app-mono Architecture Graph") -> String {
        let jsonEncoder = ArchitectureIRCodec.makeEncoder(pretty: false)
        let jsonData = (try? jsonEncoder.encode(document)) ?? Data()
        let rawStr = String(data: jsonData, encoding: .utf8) ?? "{}"
        let safeJson = rawStr.replacingOccurrences(of: "</script>", with: "<\\/script>")

        let decodedData = Data(base64Encoded: base64HTMLTemplate) ?? Data()
        let template = String(data: decodedData, encoding: .utf8) ?? ""

        return template
            .replacingOccurrences(of: "__TITLE__", with: title)
            .replacingOccurrences(of: "__NODES_COUNT__", with: String(document.nodes.count))
            .replacingOccurrences(of: "__EDGES_COUNT__", with: String(document.edges.count))
            .replacingOccurrences(of: "__JSON_DATA__", with: safeJson)
    }

    public static func renderMermaid(document: ArchitectureIRDocument, targetApp: String? = nil) -> String {
        var lines = ["```mermaid", "flowchart TD"]
        if let targetApp, let app = document.nodes.first(where: { $0.id.contains(targetApp) }) {
            appendAppMermaid(app: app, document: document, lines: &lines)
        } else {
            appendFleetMermaid(document: document, lines: &lines)
        }
        lines.append("```")
        return lines.joined(separator: "\n")
    }

    private static func appendAppMermaid(app: ArchitectureNode, document: ArchitectureIRDocument, lines: inout [String]) {
        lines.append("  subgraph App_[\"App: \(app.name)\"]")
        lines.append("    \(app.name.replacingOccurrences(of: "-", with: "_"))[\"\(app.name)\"]")
        lines.append("  end")
        let edges = document.edges.filter { $0.source == app.id }
        guard !edges.isEmpty else { return }
        lines.append("  subgraph Kits_[\"Shared SwiftKit Modules\"]")
        for e in edges {
            let kitName = e.target.replacingOccurrences(of: "swiftkit:", with: "")
            let kitId = kitName.replacingOccurrences(of: "-", with: "_")
            lines.append("    \(kitId)[\"\(kitName)\"]")
            lines.append("    \(app.name.replacingOccurrences(of: "-", with: "_")) --> \(kitId)")
        }
        lines.append("  end")
    }

    private static func appendFleetMermaid(document: ArchitectureIRDocument, lines: inout [String]) {
        lines.append("  subgraph Apps[\"Fleet Apps (\(document.nodes.filter { $0.type == .app }.count))\"]")
        for n in document.nodes.filter({ $0.type == .app }).prefix(12) {
            let id = n.name.replacingOccurrences(of: "-", with: "_")
            lines.append("    \(id)[\"\(n.name)\"]")
        }
        lines.append("  end")
        lines.append("  subgraph SwiftKits[\"SwiftKit Modules (\(document.nodes.filter { $0.type == .swiftkit }.count))\"]")
        for n in document.nodes.filter({ $0.type == .swiftkit }).prefix(10) {
            let id = n.name.replacingOccurrences(of: "-", with: "_")
            lines.append("    \(id)[\"\(n.name)\"]")
        }
        lines.append("  end")
        lines.append("  Apps ==> SwiftKits")
    }
}
