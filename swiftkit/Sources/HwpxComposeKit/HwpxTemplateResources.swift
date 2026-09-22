import Foundation

/// HWPX 패키지에 필요한 골격 XML 리소스.
/// header.xml: 글꼴 3종, 문단 스타일 6종, 표 테두리 2종.
enum HwpxTemplateResources {
    static let versionXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <opf:versionDescription xmlns:opf="\(HwpxNamespaces.opf)" version="1.1">
    <opf:application version="1.0">HwpxComposeKit</opf:application>
    </opf:versionDescription>
    """

    static let containerXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container>
    <rootfiles>
    <rootfile media-type="application/hwpx+xml" full-path="Contents/content.hpf"/>
    </rootfiles>
    </container>
    """

    static let contentHPF = """
    <?xml version="1.0" encoding="UTF-8"?>
    <opf:package xmlns:opf="\(HwpxNamespaces.opf)">
    <opf:manifest>
    <opf:item id="header" href="header.xml" media-type="application/xml"/>
    <opf:item id="section0" href="section0.xml" media-type="application/xml"/>
    </opf:manifest>
    <opf:spine>
    <opf:itemref idref="section0"/>
    </opf:spine>
    </opf:package>
    """

    static let headerXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <hp:head xmlns:hp="\(HwpxNamespaces.head)">
    <hp:fontfaces>
    <hp:fontface lang="hangul">
    <hp:font face="함초롬바탕" type="ttf" id="0"/>
    </hp:fontface>
    <hp:fontface lang="latin">
    <hp:font face="Noto Sans" type="ttf" id="1"/>
    </hp:fontface>
    <hp:fontface lang="hanja">
    <hp:font face="함초롬바탕" type="ttf" id="2"/>
    </hp:fontface>
    </hp:fontfaces>
    <hp:paraStyleList>
    <hp:paraStyle id="0" name="본문">
    <hp:charPr fontRef="0" fontSize="1000"/>
    </hp:paraStyle>
    <hp:paraStyle id="1" name="제목 1">
    <hp:charPr fontRef="0" fontSize="2000" bold="true"/>
    </hp:paraStyle>
    <hp:paraStyle id="2" name="제목 2">
    <hp:charPr fontRef="0" fontSize="1600" bold="true"/>
    </hp:paraStyle>
    <hp:paraStyle id="3" name="제목 3">
    <hp:charPr fontRef="0" fontSize="1200"/>
    </hp:paraStyle>
    <hp:paraStyle id="4" name="목록">
    <hp:charPr fontRef="0" fontSize="1000"/>
    </hp:paraStyle>
    <hp:paraStyle id="5" name="표 본문">
    <hp:charPr fontRef="0" fontSize="900"/>
    </hp:paraStyle>
    </hp:paraStyleList>
    <hp:borderFillList>
    <hp:borderFill id="1" type="solid">
    <hp:slash type="none"/>
    <hp:border>
    <hp:left type="solid" width="0.12mm" color="000000"/>
    <hp:right type="solid" width="0.12mm" color="000000"/>
    <hp:top type="solid" width="0.12mm" color="000000"/>
    <hp:bottom type="solid" width="0.12mm" color="000000"/>
    </hp:border>
    </hp:borderFill>
    <hp:borderFill id="2" type="none">
    <hp:slash type="none"/>
    </hp:borderFill>
    </hp:borderFillList>
    </hp:head>
    """
}
