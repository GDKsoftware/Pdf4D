import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.GregorianCalendar;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Map;
import java.util.TimeZone;
import java.util.TreeMap;
import java.awt.geom.GeneralPath;
import java.awt.geom.PathIterator;
import java.lang.reflect.Method;

import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;

import org.apache.fontbox.cff.CFFCIDFont;
import org.apache.fontbox.cff.CFFFont;
import org.apache.fontbox.cff.CFFType1Font;
import org.apache.fontbox.ttf.OTFParser;
import org.apache.fontbox.ttf.OpenTypeFont;
import org.apache.fontbox.ttf.TTFParser;
import org.apache.fontbox.ttf.TrueTypeFont;
import org.apache.fontbox.type1.Type1Font;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.io.RandomAccessReadBufferedFile;
import org.apache.pdfbox.cos.COSArray;
import org.apache.pdfbox.cos.COSBase;
import org.apache.pdfbox.cos.COSBoolean;
import org.apache.pdfbox.cos.COSDictionary;
import org.apache.pdfbox.cos.COSDocument;
import org.apache.pdfbox.cos.COSFloat;
import org.apache.pdfbox.cos.COSInteger;
import org.apache.pdfbox.cos.COSName;
import org.apache.pdfbox.cos.COSNull;
import org.apache.pdfbox.cos.COSObject;
import org.apache.pdfbox.cos.COSObjectKey;
import org.apache.pdfbox.cos.COSStream;
import org.apache.pdfbox.cos.COSString;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDDocumentCatalog;
import org.apache.pdfbox.pdmodel.PDDocumentInformation;
import org.apache.pdfbox.pdmodel.PDDocumentNameDictionary;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.common.PDMetadata;
import org.apache.pdfbox.pdmodel.common.PDNameTreeNode;
import org.apache.pdfbox.pdmodel.common.PDPageLabels;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.pdmodel.common.PDStream;
import org.apache.pdfbox.pdmodel.common.filespecification.PDComplexFileSpecification;
import org.apache.pdfbox.pdmodel.common.filespecification.PDEmbeddedFile;
import org.apache.pdfbox.pdmodel.encryption.AccessPermission;
import org.apache.pdfbox.pdmodel.encryption.InvalidPasswordException;
import org.apache.pdfbox.pdmodel.encryption.PDEncryption;
import org.apache.pdfbox.pdmodel.encryption.StandardProtectionPolicy;
import org.apache.pdfbox.pdmodel.encryption.StandardSecurityHandler;
import org.apache.pdfbox.pdmodel.font.FontInfo;
import org.apache.pdfbox.pdmodel.font.FontMapper;
import org.apache.pdfbox.pdmodel.font.FontMappers;
import org.apache.pdfbox.pdmodel.font.FontProvider;
import org.apache.pdfbox.pdmodel.font.PDType1Font;
import org.apache.pdfbox.pdmodel.font.Standard14Fonts;
import org.apache.pdfbox.pdmodel.interactive.documentnavigation.outline.PDDocumentOutline;
import org.apache.pdfbox.pdmodel.interactive.documentnavigation.outline.PDOutlineItem;
import org.apache.pdfbox.pdmodel.interactive.documentnavigation.outline.PDOutlineNode;
import org.apache.pdfbox.pdmodel.interactive.form.PDAcroForm;
import org.apache.pdfbox.pdmodel.interactive.form.PDCheckBox;
import org.apache.pdfbox.pdmodel.interactive.form.PDChoice;
import org.apache.pdfbox.pdmodel.interactive.form.PDComboBox;
import org.apache.pdfbox.pdmodel.interactive.form.PDField;
import org.apache.pdfbox.pdmodel.interactive.form.PDListBox;
import org.apache.pdfbox.pdmodel.interactive.form.PDNonTerminalField;
import org.apache.pdfbox.pdmodel.interactive.form.PDPushButton;
import org.apache.pdfbox.pdmodel.interactive.form.PDRadioButton;
import org.apache.pdfbox.pdmodel.interactive.form.PDSignatureField;
import org.apache.pdfbox.pdmodel.interactive.form.PDTextField;
import org.apache.pdfbox.text.PDFTextStripper;
import org.apache.pdfbox.text.TextPosition;

/**
 * Pdf4D golden oracle. Writes the canonical dump format described in docs/golden-format.md.
 *
 * Usage:
 *   java -cp lib/pdfbox-app-3.0.8.jar Pdf4DOracle.java dump    file.pdf [password]
 *   java -cp lib/pdfbox-app-3.0.8.jar Pdf4DOracle.java --prepare out.pdf
 *   java -cp lib/pdfbox-app-3.0.8.jar Pdf4DOracle.java --encrypt in.pdf out.pdf user owner alg [--nometa]
 *   java -cp lib/pdfbox-app-3.0.8.jar Pdf4DOracle.java text    file.pdf [password]
 *   java -cp lib/pdfbox-app-3.0.8.jar Pdf4DOracle.java positions file.pdf [password]
 *   java -cp lib/pdfbox-app-3.0.8.jar Pdf4DOracle.java --font-widths font.(ttf|otf|pfb)
 *   java -cp lib/pdfbox-app-3.0.8.jar Pdf4DOracle.java --glyph-paths font.(otf|pfb)
 *   (a bare "file.pdf [password]" is the same as "dump")
 *
 * Every mode runs with a hermetic font mapper: no system fonts, only embedded fonts, the standard 14
 * and the LiberationSans fallback of PDFBox.
 */
public class Pdf4DOracle
{
    private static final List<String> IMAGE_FILTERS = List.of("DCTDecode", "DCT", "JPXDecode",
            "JBIG2Decode", "CCITTFaxDecode", "CCF");

    public static void main(String[] args) throws Exception
    {
        PrintStream out = new PrintStream(System.out, false, "UTF-8");
        try
        {
            makeFontsHermetic();
        }
        catch (Throwable t)
        {
            // Never a golden: without the hermetic setup every result would depend on the installed fonts
            System.err.println("Cannot set up the hermetic font mapper");
            t.printStackTrace();
            System.exit(1);
        }
        try
        {
            if (args.length >= 2 && args[0].equals("--font-widths"))
            {
                out.print(fontWidths(new File(args[1])));
            }
            else if (args.length >= 2 && args[0].equals("--glyph-paths"))
            {
                out.print(glyphPaths(new File(args[1])));
            }
            else if (args.length >= 2 && args[0].equals("text"))
            {
                out.print(text(new File(args[1]), args.length > 2 ? args[2] : ""));
            }
            else if (args.length >= 2 && args[0].equals("positions"))
            {
                out.print(positions(new File(args[1]), args.length > 2 ? args[2] : ""));
            }
            else if (args.length >= 2 && args[0].equals("--prepare"))
            {
                prepareBase(new File(args[1]));
            }
            else if (args.length >= 6 && args[0].equals("--encrypt"))
            {
                encrypt(new File(args[1]), new File(args[2]), pw(args[3]), pw(args[4]), args[5],
                        args.length > 6 && args[6].equals("--nometa"));
            }
            else
            {
                int i = args.length > 0 && args[0].equals("dump") ? 1 : 0;
                String password = args.length > i + 1 ? args[i + 1] : "";
                out.print(dump(new File(args[i]), password));
            }
        }
        catch (Throwable t)
        {
            if (args.length > 0 && (args[0].startsWith("--")))
            {
                t.printStackTrace();
                System.exit(1);
            }
            out.print("load-error: parse\n");
        }
        out.flush();
        System.exit(0);
    }

    /** "<empty>" stands for the empty password (an empty command line argument gets lost on Windows). */
    static String pw(String s)
    {
        return s.equals("<empty>") ? "" : s;
    }

    // ------------------------------------------------------------------ dump

    static String dump(File file, String password)
    {
        StringBuilder sb = new StringBuilder();
        PDDocument doc;
        try
        {
            doc = Loader.loadPDF(file, password);
        }
        catch (InvalidPasswordException e)
        {
            return "load-error: wrong-password\n";
        }
        catch (Throwable t)
        {
            return "load-error: " + classifyLoadError(t) + "\n";
        }
        try (doc)
        {
            dumpDocument(doc, sb);
        }
        catch (Throwable t)
        {
            // dumpDocument guards every section itself; this only catches a failing close
        }
        return sb.toString();
    }

    static String classifyLoadError(Throwable t)
    {
        for (Throwable c = t; c != null; c = c.getCause())
        {
            if (c instanceof InvalidPasswordException)
            {
                return "wrong-password";
            }
            String m = c.getMessage() == null ? "" : c.getMessage().toLowerCase();
            if (m.contains("security handler") || m.contains("unsupported") || m.contains("not supported")
                    || m.contains("unknown encryption") || m.contains("unknown algorithm")
                    || m.contains("public key") || m.contains("decryption material"))
            {
                return "unsupported";
            }
        }
        return "parse";
    }

    static void dumpDocument(PDDocument doc, StringBuilder sb)
    {
        // version
        try
        {
            sb.append("version: ").append(Float.toString(doc.getVersion())).append('\n');
        }
        catch (Throwable t)
        {
            sb.append("version: error\n");
        }
        // encrypted, permissions
        boolean encrypted = doc.isEncrypted();
        sb.append("encrypted: ").append(encrypted).append('\n');
        String perms = "none";
        if (encrypted)
        {
            try
            {
                perms = Integer.toString(doc.getEncryption().getPermissions());
            }
            catch (Throwable t)
            {
                perms = "error";
            }
        }
        sb.append("permissions: ").append(perms).append('\n');

        PDDocumentCatalog catalog = null;
        try
        {
            catalog = doc.getDocumentCatalog();
        }
        catch (Throwable t)
        {
            // handled below
        }

        // pages
        List<PDPage> pages = new ArrayList<>();
        boolean pagesFailed = false;
        try
        {
            for (PDPage p : doc.getPages())
            {
                pages.add(p);
            }
        }
        catch (Throwable t)
        {
            pagesFailed = true;
        }
        sb.append("pages: ").append(pagesFailed && pages.isEmpty() ? "error" : Integer.toString(pages.size()))
                .append('\n');
        String[] labels = null;
        try
        {
            PDPageLabels pageLabels = catalog == null ? null : catalog.getPageLabels();
            if (pageLabels != null)
            {
                labels = pageLabels.getLabelsByPageIndices();
            }
        }
        catch (Throwable t)
        {
            labels = null;
        }
        for (int i = 0; i < pages.size(); i++)
        {
            PDPage p = pages.get(i);
            try
            {
                String label = labels != null && i < labels.length && labels[i] != null ? labels[i] : "";
                sb.append("page ").append(i + 1).append(": media=").append(rect(p.getMediaBox()))
                        .append(" crop=").append(rect(p.getCropBox()))
                        .append(" rotate=").append(p.getRotation())
                        .append(" label=").append(escapeText(label)).append('\n');
            }
            catch (Throwable t)
            {
                sb.append("page ").append(i + 1).append(": error\n");
            }
        }

        // info
        dumpInfo(doc, sb);

        // xmp
        String xmp = "none";
        try
        {
            if (catalog != null)
            {
                PDMetadata md = catalog.getMetadata();
                if (md != null)
                {
                    xmp = Integer.toString(md.exportXMPMetadata().available());
                }
            }
        }
        catch (Throwable t)
        {
            xmp = "error";
        }
        sb.append("xmp: ").append(xmp).append('\n');

        // outline
        try
        {
            PDDocumentOutline outline = catalog == null ? null : catalog.getDocumentOutline();
            if (outline != null)
            {
                dumpOutline(doc, pages, outline, 0, sb, new IdentityHashMap<>());
            }
        }
        catch (Throwable t)
        {
            sb.append("outline: error\n");
        }

        // fields
        try
        {
            PDAcroForm form = catalog == null ? null : catalog.getAcroForm(null);
            if (form != null)
            {
                for (PDField f : form.getFieldTree())
                {
                    dumpField(f, sb);
                }
            }
        }
        catch (Throwable t)
        {
            sb.append("field: error\n");
        }

        // attachments
        try
        {
            PDDocumentNameDictionary names = catalog == null ? null : catalog.getNames();
            if (names != null && names.getEmbeddedFiles() != null)
            {
                dumpAttachments(names.getEmbeddedFiles(), sb, 0);
            }
        }
        catch (Throwable t)
        {
            sb.append("attachment: error\n");
        }

        // objects
        dumpObjects(doc, sb);
    }

    static void dumpInfo(PDDocument doc, StringBuilder sb)
    {
        try
        {
            COSBase infoBase = doc.getDocument().getTrailer().getDictionaryObject(COSName.INFO);
            if (!(infoBase instanceof COSDictionary))
            {
                return;
            }
            COSDictionary info = (COSDictionary) infoBase;
            TreeMap<String, String> lines = new TreeMap<>();
            for (Map.Entry<COSName, COSBase> e : info.entrySet())
            {
                String key = nameText(e.getKey().getName());
                String value;
                try
                {
                    COSBase v = info.getDictionaryObject(e.getKey());
                    if (v instanceof COSString)
                    {
                        String iso = null;
                        if (e.getKey().equals(COSName.CREATION_DATE) || e.getKey().equals(COSName.MOD_DATE))
                        {
                            Calendar c = info.getDate(e.getKey());
                            if (c != null)
                            {
                                iso = isoDate(c);
                            }
                        }
                        value = iso != null ? iso : escapeText(((COSString) v).getString());
                    }
                    else
                    {
                        value = canonical(v);
                    }
                }
                catch (Throwable t)
                {
                    value = "<error>";
                }
                lines.put(key, value);
            }
            for (Map.Entry<String, String> e : lines.entrySet())
            {
                sb.append("info ").append(e.getKey()).append(": ").append(e.getValue()).append('\n');
            }
        }
        catch (Throwable t)
        {
            sb.append("info: error\n");
        }
    }

    static String isoDate(Calendar c)
    {
        int offset = c.get(Calendar.ZONE_OFFSET) + c.get(Calendar.DST_OFFSET);
        int minutes = Math.abs(offset) / 60000;
        return String.format("%04d-%02d-%02dT%02d:%02d:%02d%s%02d:%02d", c.get(Calendar.YEAR),
                c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH), c.get(Calendar.HOUR_OF_DAY),
                c.get(Calendar.MINUTE), c.get(Calendar.SECOND), offset < 0 ? "-" : "+", minutes / 60,
                minutes % 60);
    }

    static void dumpOutline(PDDocument doc, List<PDPage> pages, PDOutlineNode node, int level,
            StringBuilder sb, IdentityHashMap<COSDictionary, Boolean> seen) throws IOException
    {
        for (PDOutlineItem item : node.children())
        {
            if (seen.put(item.getCOSObject(), Boolean.TRUE) != null || level > 64)
            {
                continue;
            }
            String title = item.getTitle();
            String target = "?";
            try
            {
                PDPage page = item.findDestinationPage(doc);
                if (page != null)
                {
                    int idx = -1;
                    for (int i = 0; i < pages.size(); i++)
                    {
                        if (pages.get(i).getCOSObject() == page.getCOSObject())
                        {
                            idx = i;
                            break;
                        }
                    }
                    if (idx >= 0)
                    {
                        target = Integer.toString(idx + 1);
                    }
                }
            }
            catch (Throwable t)
            {
                target = "?";
            }
            sb.append("outline: ");
            for (int i = 0; i < level; i++)
            {
                sb.append("  ");
            }
            sb.append(escapeText(title == null ? "" : title)).append(" -> ").append(target).append('\n');
            dumpOutline(doc, pages, item, level + 1, sb, seen);
        }
    }

    static void dumpField(PDField f, StringBuilder sb)
    {
        String name;
        String kind;
        String value = "";
        try
        {
            name = escapeText(f.getFullyQualifiedName());
        }
        catch (Throwable t)
        {
            name = "<error>";
        }
        if (f instanceof PDNonTerminalField)
        {
            kind = "nonterminal";
        }
        else if (f instanceof PDCheckBox)
        {
            kind = "checkbox";
        }
        else if (f instanceof PDRadioButton)
        {
            kind = "radio";
        }
        else if (f instanceof PDPushButton)
        {
            kind = "pushbutton";
        }
        else if (f instanceof PDComboBox)
        {
            kind = "combo";
        }
        else if (f instanceof PDListBox)
        {
            kind = "list";
        }
        else if (f instanceof PDTextField)
        {
            kind = "text";
        }
        else if (f instanceof PDSignatureField)
        {
            kind = "signature";
        }
        else
        {
            kind = "unknown";
        }
        try
        {
            if (f instanceof PDNonTerminalField)
            {
                value = "";
            }
            else if (f instanceof PDChoice)
            {
                List<String> vals = ((PDChoice) f).getValue();
                StringBuilder v = new StringBuilder();
                for (int i = 0; i < vals.size(); i++)
                {
                    if (i > 0)
                    {
                        v.append(',');
                    }
                    v.append(escapeText(vals.get(i)));
                }
                value = v.toString();
            }
            else
            {
                String s = f.getValueAsString();
                value = escapeText(s == null ? "" : s);
            }
        }
        catch (Throwable t)
        {
            value = "<error>";
        }
        sb.append("field: ").append(name).append(" | ").append(kind).append(" | ").append(value).append('\n');
    }

    static void dumpAttachments(PDNameTreeNode<PDComplexFileSpecification> node, StringBuilder sb, int depth)
            throws IOException
    {
        if (depth > 64)
        {
            return;
        }
        List<PDNameTreeNode<PDComplexFileSpecification>> kids = node.getKids();
        if (kids != null)
        {
            for (PDNameTreeNode<PDComplexFileSpecification> kid : kids)
            {
                dumpAttachments(kid, sb, depth + 1);
            }
            return;
        }
        Map<String, PDComplexFileSpecification> names = node.getNames();
        if (names == null)
        {
            return;
        }
        for (Map.Entry<String, PDComplexFileSpecification> e : names.entrySet())
        {
            String fileName = e.getKey();
            String size = "?";
            try
            {
                PDComplexFileSpecification spec = e.getValue();
                String fn = spec.getFilename();
                if (fn != null)
                {
                    fileName = fn;
                }
                PDEmbeddedFile ef = spec.getEmbeddedFile();
                if (ef != null && ef.getSize() >= 0)
                {
                    size = Integer.toString(ef.getSize());
                }
            }
            catch (Throwable t)
            {
                // keep defaults
            }
            sb.append("attachment: ").append(escapeText(fileName)).append(" | ").append(size).append('\n');
        }
    }

    static void dumpObjects(PDDocument doc, StringBuilder sb)
    {
        COSDocument cos = doc.getDocument();
        List<COSObjectKey> keys = new ArrayList<>(cos.getXrefTable().keySet());
        Collections.sort(keys, (a, b) -> a.getNumber() != b.getNumber()
                ? Long.compare(a.getNumber(), b.getNumber())
                : Integer.compare(a.getGeneration(), b.getGeneration()));
        for (COSObjectKey key : keys)
        {
            String prefix = "object " + key.getNumber() + " " + key.getGeneration() + ": ";
            try
            {
                COSBase base = cos.getObjectFromPool(key).getObject();
                if (base == null)
                {
                    sb.append(prefix).append("error\n");
                    continue;
                }
                if (base instanceof COSDictionary)
                {
                    COSBase type = ((COSDictionary) base).getDictionaryObject(COSName.TYPE);
                    if (COSName.OBJ_STM.equals(type) || COSName.XREF.equals(type))
                    {
                        continue; // structural stream carriers are not part of the dump
                    }
                }
                sb.append(prefix).append(canonicalTop(base)).append('\n');
            }
            catch (Throwable t)
            {
                sb.append(prefix).append("error\n");
            }
        }
    }

    // ------------------------------------------------------- canonical form

    static String canonicalTop(COSBase base) throws IOException
    {
        if (base instanceof COSStream)
        {
            return canonicalStream((COSStream) base);
        }
        return canonical(base);
    }

    static String canonicalStream(COSStream stream) throws IOException
    {
        String dict = canonicalDictionary(stream);
        try
        {
            PDStream pd = new PDStream(stream);
            List<COSName> filters = pd.getFilters();
            int stop = -1;
            for (int i = 0; i < filters.size(); i++)
            {
                if (IMAGE_FILTERS.contains(filters.get(i).getName()))
                {
                    stop = i;
                    break;
                }
            }
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            try (InputStream is = pd.createInputStream(IMAGE_FILTERS))
            {
                byte[] buf = new byte[65536];
                int n;
                while ((n = is.read(buf)) > 0)
                {
                    md.update(buf, 0, n);
                }
            }
            StringBuilder r = new StringBuilder(dict).append(" stream");
            if (stop >= 0)
            {
                r.append(" partial=");
                for (int i = stop; i < filters.size(); i++)
                {
                    if (i > stop)
                    {
                        r.append(',');
                    }
                    r.append(filters.get(i).getName());
                }
            }
            return r.append(" sha256=").append(hex(md.digest())).toString();
        }
        catch (Throwable t)
        {
            return dict + " stream error";
        }
    }

    static String canonicalDictionary(COSDictionary d) throws IOException
    {
        TreeMap<String, String> sorted = new TreeMap<>();
        for (Map.Entry<COSName, COSBase> e : d.entrySet())
        {
            sorted.put(nameText(e.getKey().getName()), canonical(e.getValue()));
        }
        StringBuilder sb = new StringBuilder("<<");
        boolean first = true;
        for (Map.Entry<String, String> e : sorted.entrySet())
        {
            if (!first)
            {
                sb.append(' ');
            }
            first = false;
            sb.append('/').append(e.getKey()).append(' ').append(e.getValue());
        }
        return sb.append(">>").toString();
    }

    static String canonical(COSBase b) throws IOException
    {
        if (b == null || b instanceof COSNull)
        {
            return "null";
        }
        if (b instanceof COSObject)
        {
            COSObjectKey k = ((COSObject) b).getKey();
            return k.getNumber() + " " + k.getGeneration() + " R";
        }
        if (b instanceof COSBoolean)
        {
            return ((COSBoolean) b).getValue() ? "true" : "false";
        }
        if (b instanceof COSInteger)
        {
            return Long.toString(((COSInteger) b).longValue());
        }
        if (b instanceof COSFloat)
        {
            return num(((COSFloat) b).floatValue());
        }
        if (b instanceof COSName)
        {
            return "/" + nameText(((COSName) b).getName());
        }
        if (b instanceof COSString)
        {
            return "<" + hex(((COSString) b).getBytes()) + ">";
        }
        if (b instanceof COSArray)
        {
            StringBuilder sb = new StringBuilder("[");
            boolean first = true;
            for (COSBase item : (COSArray) b)
            {
                if (!first)
                {
                    sb.append(' ');
                }
                first = false;
                sb.append(canonical(item));
            }
            return sb.append(']').toString();
        }
        if (b instanceof COSDictionary)
        {
            return canonicalDictionary((COSDictionary) b);
        }
        throw new IOException("unsupported COS type " + b.getClass());
    }

    // ------------------------------------------------------- hermetic fonts

    /**
     * Gives the font mapper a provider without fonts, so that the machine's installed fonts never play
     * a role: only embedded fonts, the standard 14 and the built-in LiberationSans fallback remain.
     */
    static void makeFontsHermetic() throws Exception
    {
        FontMapper mapper = FontMappers.instance();
        FontProvider empty = new FontProvider()
        {
            @Override
            public String toDebugString()
            {
                return "empty";
            }

            @Override
            public List<? extends FontInfo> getFontInfo()
            {
                return new ArrayList<FontInfo>();
            }
        };
        // FontMapperImpl is package private, so the method is reached by reflection
        Method setProvider = mapper.getClass().getMethod("setProvider", FontProvider.class);
        setProvider.setAccessible(true);
        setProvider.invoke(mapper, empty);
    }

    // ------------------------------------------------------------------ text

    static String text(File file, String password)
    {
        PDDocument doc;
        try
        {
            doc = Loader.loadPDF(file, password);
        }
        catch (InvalidPasswordException e)
        {
            return "load-error: wrong-password\n";
        }
        catch (Throwable t)
        {
            return "load-error: " + classifyLoadError(t) + "\n";
        }
        StringBuilder sb = new StringBuilder();
        try (doc)
        {
            int pageCount = 0;
            try
            {
                for (PDPage p : doc.getPages())
                {
                    pageCount++;
                }
            }
            catch (Throwable t)
            {
                // the pages found so far count, like in the dump
            }
            int last = Math.min(pageCount, 50);
            for (int n = 1; n <= last; n++)
            {
                textSection(doc, sb, "text: default page " + n, n, n, false, false);
            }
            for (int n = 1; n <= last; n++)
            {
                textSection(doc, sb, "text: sorted page " + n, n, n, true, false);
            }
            textSection(doc, sb, "text: range 2-3", 2, 3, false, false);
            textSection(doc, sb, "text: separators 1-2", 1, 2, false, true);
        }
        catch (Throwable t)
        {
            // only a failing close ends here
        }
        return sb.toString();
    }

    static void textSection(PDDocument doc, StringBuilder sb, String heading, int start, int end,
            boolean sorted, boolean separators)
    {
        sb.append(heading).append('\n');
        String text;
        try
        {
            PDFTextStripper stripper = new PDFTextStripper();
            stripper.setSortByPosition(sorted);
            stripper.setStartPage(start);
            stripper.setEndPage(end);
            if (separators)
            {
                stripper.setLineSeparator("<EOL>\n");
                stripper.setWordSeparator("<W>");
                stripper.setParagraphStart("<P>");
                stripper.setParagraphEnd("</P>");
                stripper.setPageStart("<PAGE>");
                stripper.setPageEnd("</PAGE>\n");
                stripper.setArticleStart("<A>");
                stripper.setArticleEnd("</A>");
            }
            else
            {
                stripper.setLineSeparator("\n");
                stripper.setPageEnd("\n");
            }
            text = stripper.getText(doc);
        }
        catch (Throwable t)
        {
            sb.append("error\n");
            return;
        }
        String[] lines = text.split("\n", -1);
        int count = lines.length;
        if (count > 0 && lines[count - 1].isEmpty())
        {
            count--;
        }
        for (int i = 0; i < count; i++)
        {
            String line = lines[i];
            if (line.isEmpty())
            {
                sb.append("|\n");
                continue;
            }
            String escaped = escapeText(line);
            if (line.endsWith(" "))
            {
                escaped = escaped.substring(0, escaped.length() - 1) + "\\x20";
            }
            sb.append("| ").append(escaped).append('\n');
        }
    }

    // ------------------------------------------------------------- positions

    /** Collects per line of the stripper the first and last glyph position (docs/golden-format.md, "Position goldens"). */
    static class PositionStripper extends PDFTextStripper
    {
        final StringBuilder sb = new StringBuilder();
        private TextPosition first;
        private TextPosition last;
        private int glyphs;

        PositionStripper() throws IOException
        {
            super();
        }

        @Override
        protected void startPage(PDPage page) throws IOException
        {
            sb.append("page ").append(getCurrentPageNo()).append('\n');
            super.startPage(page);
        }

        @Override
        protected void endPage(PDPage page) throws IOException
        {
            flushLine();
            super.endPage(page);
        }

        @Override
        protected void writeLineSeparator() throws IOException
        {
            flushLine();
            super.writeLineSeparator();
        }

        @Override
        protected void writeString(String text, List<TextPosition> textPositions) throws IOException
        {
            if (!textPositions.isEmpty())
            {
                if (first == null)
                {
                    first = textPositions.get(0);
                }
                last = textPositions.get(textPositions.size() - 1);
                glyphs += textPositions.size();
            }
            super.writeString(text, textPositions);
        }

        private void flushLine()
        {
            if (glyphs > 0)
            {
                sb.append("line: ").append(fixed2(first.getTextMatrix().getTranslateX())).append(' ')
                        .append(fixed2(first.getTextMatrix().getTranslateY())).append(' ')
                        .append(fixed2(last.getEndX())).append(' ').append(fixed2(last.getEndY())).append(' ')
                        .append(glyphs).append('\n');
            }
            first = null;
            last = null;
            glyphs = 0;
        }
    }

    static String fixed2(float f)
    {
        return String.format(java.util.Locale.ROOT, "%.2f", f);
    }

    static String positions(File file, String password)
    {
        PDDocument doc;
        try
        {
            doc = Loader.loadPDF(file, password);
        }
        catch (InvalidPasswordException e)
        {
            return "load-error: wrong-password\n";
        }
        catch (Throwable t)
        {
            return "load-error: " + classifyLoadError(t) + "\n";
        }
        try (doc)
        {
            int pageCount = 0;
            try
            {
                for (PDPage p : doc.getPages())
                {
                    pageCount++;
                }
            }
            catch (Throwable t)
            {
                // the pages found so far count, like in the dump
            }
            PositionStripper stripper = new PositionStripper();
            stripper.setSortByPosition(true);
            stripper.setStartPage(1);
            stripper.setEndPage(Math.min(pageCount, 50));
            try
            {
                stripper.getText(doc);
            }
            catch (Throwable t)
            {
                stripper.sb.append("error\n");
            }
            return stripper.sb.toString();
        }
        catch (Throwable t)
        {
            return "load-error: parse\n";
        }
    }

    // ---------------------------------------------------------- font widths

    static String fontWidths(File file) throws Exception
    {
        String name = file.getName().toLowerCase();
        TreeMap<String, String> widths = new TreeMap<>();
        if (name.endsWith(".pfb"))
        {
            Type1Font font = Type1Font.createWithPFB(java.nio.file.Files.readAllBytes(file.toPath()));
            for (String glyph : font.getCharStringsDict().keySet())
            {
                widths.put(glyph, num(font.getWidth(glyph)));
            }
        }
        else if (name.endsWith(".otf"))
        {
            try (OpenTypeFont font = new OTFParser().parse(new RandomAccessReadBufferedFile(file)))
            {
                if (font.isPostScript())
                {
                    CFFFont cff = font.getCFF().getFont();
                    int n = cff.getNumCharStrings();
                    for (int gid = 0; gid < n; gid++)
                    {
                        widths.put("gid" + gid, Integer.toString(cff.getType2CharString(gid).getWidth()));
                    }
                }
                else
                {
                    ttfWidths(font, widths);
                }
            }
        }
        else
        {
            try (TrueTypeFont font = new TTFParser().parse(new RandomAccessReadBufferedFile(file)))
            {
                ttfWidths(font, widths);
            }
        }
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, String> e : widths.entrySet())
        {
            sb.append(e.getKey()).append(' ').append(e.getValue()).append('\n');
        }
        return sb.toString();
    }

    // ---------------------------------------------------------- glyph paths

    private static final int PATH_GLYPH_LIMIT = 300;

    static String glyphPaths(File file) throws Exception
    {
        String name = file.getName().toLowerCase();
        TreeMap<String, String> paths = new TreeMap<>();
        if (name.endsWith(".pfb"))
        {
            Type1Font font = Type1Font.createWithPFB(java.nio.file.Files.readAllBytes(file.toPath()));
            TreeMap<String, Boolean> glyphs = new TreeMap<>();
            for (String glyph : font.getCharStringsDict().keySet())
            {
                glyphs.put(glyph, Boolean.TRUE);
            }
            int count = 0;
            for (String glyph : glyphs.keySet())
            {
                if (count++ >= PATH_GLYPH_LIMIT)
                {
                    break;
                }
                try
                {
                    putPath(paths, glyph, font.getPath(glyph));
                }
                catch (Exception e)
                {
                    // left out
                }
            }
        }
        else if (name.endsWith(".otf"))
        {
            try (OpenTypeFont font = new OTFParser().parse(new RandomAccessReadBufferedFile(file)))
            {
                CFFFont cff = font.getCFF().getFont();
                int n = Math.min(cff.getNumCharStrings(), PATH_GLYPH_LIMIT);
                for (int gid = 0; gid < n; gid++)
                {
                    try
                    {
                        if (cff instanceof CFFCIDFont)
                        {
                            CFFCIDFont cid = (CFFCIDFont) cff;
                            int cidValue = cid.getCharset().getCIDForGID(gid);
                            putPath(paths, "cid" + cidValue, cid.getType2CharString(cidValue).getPath());
                        }
                        else
                        {
                            putPath(paths, "gid" + gid, ((CFFType1Font) cff).getType2CharString(gid).getPath());
                        }
                    }
                    catch (Exception e)
                    {
                        // left out
                    }
                }
            }
        }
        else
        {
            throw new IOException("Glyph paths are written for Type 1 and CFF fonts only");
        }
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, String> e : paths.entrySet())
        {
            sb.append(e.getKey()).append(e.getValue()).append('\n');
        }
        return sb.toString();
    }

    // A glyph whose charstring PDFBox cannot turn into a path is left out of the file
    static void putPath(TreeMap<String, String> paths, String key, GeneralPath path)
    {
        StringBuilder sb = new StringBuilder();
        float[] c = new float[6];
        for (PathIterator it = path.getPathIterator(null); !it.isDone(); it.next())
        {
            switch (it.currentSegment(c))
            {
            case PathIterator.SEG_MOVETO:
                sb.append(" M ").append(num(c[0])).append(' ').append(num(c[1]));
                break;
            case PathIterator.SEG_LINETO:
                sb.append(" L ").append(num(c[0])).append(' ').append(num(c[1]));
                break;
            case PathIterator.SEG_QUADTO:
                sb.append(" Q ").append(num(c[0])).append(' ').append(num(c[1])).append(' ')
                        .append(num(c[2])).append(' ').append(num(c[3]));
                break;
            case PathIterator.SEG_CUBICTO:
                sb.append(" C ").append(num(c[0])).append(' ').append(num(c[1])).append(' ')
                        .append(num(c[2])).append(' ').append(num(c[3])).append(' ')
                        .append(num(c[4])).append(' ').append(num(c[5]));
                break;
            default:
                sb.append(" Z");
                break;
            }
        }
        paths.put(key, sb.toString());
    }

    static void ttfWidths(TrueTypeFont font, TreeMap<String, String> widths) throws IOException
    {
        int n = font.getNumberOfGlyphs();
        for (int gid = 0; gid < n; gid++)
        {
            widths.put("gid" + gid, Integer.toString(font.getAdvanceWidth(gid)));
        }
    }

    // ------------------------------------------------------------ helpers

    static String num(float f)
    {
        if (Float.isNaN(f) || Float.isInfinite(f))
        {
            return Float.toString(f);
        }
        BigDecimal bd = new BigDecimal(Float.toString(f)).setScale(4, RoundingMode.HALF_UP);
        if (bd.signum() == 0)
        {
            return "0";
        }
        return bd.stripTrailingZeros().toPlainString();
    }

    static String rect(PDRectangle r)
    {
        return "[" + num(r.getLowerLeftX()) + " " + num(r.getLowerLeftY()) + " " + num(r.getUpperRightX())
                + " " + num(r.getUpperRightY()) + "]";
    }

    /** Name text: bytes outside 0x21..0x7E and the PDF delimiters/# become #XX of the UTF-8 bytes. */
    static String nameText(String name)
    {
        StringBuilder sb = new StringBuilder();
        for (byte by : name.getBytes(StandardCharsets.UTF_8))
        {
            int c = by & 0xFF;
            if (c < 0x21 || c > 0x7E || "#()<>[]{}/%".indexOf(c) >= 0)
            {
                sb.append('#').append(String.format("%02X", c));
            }
            else
            {
                sb.append((char) c);
            }
        }
        return sb.toString();
    }

    /** Text value: backslash, LF, CR, TAB and other control characters are escaped; rest verbatim. */
    static String escapeText(String s)
    {
        if (s == null)
        {
            return "";
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < s.length(); i++)
        {
            char c = s.charAt(i);
            switch (c)
            {
            case '\\':
                sb.append("\\\\");
                break;
            case '\n':
                sb.append("\\n");
                break;
            case '\r':
                sb.append("\\r");
                break;
            case '\t':
                sb.append("\\t");
                break;
            default:
                if (c < 0x20 || c == 0x7F)
                {
                    sb.append(String.format("\\x%02X", (int) c));
                }
                else
                {
                    sb.append(c);
                }
            }
        }
        return sb.toString();
    }

    static String hex(byte[] data)
    {
        char[] digits = "0123456789abcdef".toCharArray();
        char[] out = new char[data.length * 2];
        for (int i = 0; i < data.length; i++)
        {
            out[2 * i] = digits[(data[i] >> 4) & 0xF];
            out[2 * i + 1] = digits[data[i] & 0xF];
        }
        return new String(out);
    }

    // ------------------------------------------------- base file / encryption

    static final String XMP = "<?xpacket begin=\"﻿\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n"
            + "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">"
            + "<rdf:Description rdf:about=\"\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\">"
            + "<dc:title><rdf:Alt><rdf:li xml:lang=\"x-default\">Pdf4D encrypted base</rdf:li></rdf:Alt></dc:title>"
            + "</rdf:Description></rdf:RDF></x:xmpmeta>\n<?xpacket end=\"w\"?>";

    /** Builds the small unencrypted base file used for the encrypted variants. */
    static void prepareBase(File out) throws IOException
    {
        try (PDDocument doc = new PDDocument())
        {
            for (int i = 1; i <= 2; i++)
            {
                PDPage page = new PDPage(PDRectangle.A4);
                doc.addPage(page);
                try (PDPageContentStream cs = new PDPageContentStream(doc, page))
                {
                    cs.beginText();
                    cs.setFont(new PDType1Font(Standard14Fonts.FontName.HELVETICA), 12);
                    cs.newLineAtOffset(72, 720);
                    cs.showText("Pdf4D encrypted base, page " + i);
                    cs.endText();
                }
            }
            PDDocumentInformation info = new PDDocumentInformation();
            info.setTitle("Pdf4D encrypted base");
            info.setAuthor("Tëst Åuthor");
            info.setProducer("Pdf4D test generator");
            info.setCreationDate(new GregorianCalendar(TimeZone.getTimeZone("GMT+01:00")) {
                {
                    clear();
                    set(2024, Calendar.JANUARY, 2, 3, 4, 5);
                }
            });
            doc.setDocumentInformation(info);
            PDMetadata md = new PDMetadata(doc);
            md.importXMPMetadata(XMP.getBytes(StandardCharsets.UTF_8));
            doc.getDocumentCatalog().setMetadata(md);
            doc.save(out);
        }
    }

    /** Standard security handler that leaves the XMP metadata stream unencrypted (EncryptMetadata false). */
    static class NoMetadataHandler
            extends org.apache.pdfbox.pdmodel.encryption.SecurityHandler<StandardProtectionPolicy>
    {
        private final StandardSecurityHandler inner;

        NoMetadataHandler(StandardProtectionPolicy policy)
        {
            super(policy);
            inner = new StandardSecurityHandler(policy);
        }

        @Override
        public void prepareForDecryption(PDEncryption encryption, COSArray ids,
                org.apache.pdfbox.pdmodel.encryption.DecryptionMaterial material) throws IOException
        {
            throw new IOException("not supported");
        }

        @Override
        public void prepareDocumentForEncryption(PDDocument document) throws IOException
        {
            inner.prepareDocumentForEncryption(document);
            setKeyLength(inner.getKeyLength());
            setAES(true);
            setEncryptionKey(inner.getEncryptionKey());
            setStreamFilterName(COSName.STD_CF);
            setStringFilterName(COSName.STD_CF);
            PDEncryption enc = document.getEncryption();
            enc.getCOSObject().setBoolean(COSName.ENCRYPT_META_DATA, false);
            try
            {
                // Perms byte 8 states whether metadata is encrypted: 'T' -> 'F'. Single block, zero IV == ECB.
                SecretKeySpec key = new SecretKeySpec(getEncryptionKey(), "AES");
                Cipher c = Cipher.getInstance("AES/ECB/NoPadding");
                c.init(Cipher.DECRYPT_MODE, key);
                byte[] perms = c.doFinal(enc.getPerms());
                perms[8] = 'F';
                c.init(Cipher.ENCRYPT_MODE, key);
                enc.setPerms(c.doFinal(perms));
            }
            catch (java.security.GeneralSecurityException e)
            {
                throw new IOException(e);
            }
        }

        @Override
        public void encryptStream(COSStream stream, long objNum, int genNum) throws IOException
        {
            if (COSName.METADATA.equals(stream.getCOSName(COSName.TYPE)))
            {
                return;
            }
            super.encryptStream(stream, objNum, genNum);
        }
    }

    static void encrypt(File in, File out, String user, String owner, String alg, boolean noMeta)
            throws IOException
    {
        try (PDDocument doc = Loader.loadPDF(in))
        {
            AccessPermission ap = new AccessPermission();
            int keyLength;
            boolean aes;
            switch (alg)
            {
            case "rc4-40":
                keyLength = 40;
                aes = false;
                // R2 is only chosen when no revision 3 permission is set
                ap.setCanFillInForm(false);
                ap.setCanExtractForAccessibility(false);
                ap.setCanAssembleDocument(false);
                ap.setCanPrintFaithful(false);
                break;
            case "rc4-128":
                keyLength = 128;
                aes = false;
                break;
            case "aes-128":
                keyLength = 128;
                aes = true;
                break;
            case "aes-256":
                keyLength = 256;
                aes = true;
                break;
            default:
                throw new IllegalArgumentException("unknown algorithm " + alg);
            }
            StandardProtectionPolicy policy = new StandardProtectionPolicy(owner, user, ap);
            policy.setEncryptionKeyLength(keyLength);
            policy.setPreferAES(aes);
            if (noMeta)
            {
                if (keyLength != 256)
                {
                    throw new IllegalArgumentException("--nometa is only supported for aes-256");
                }
                if (!doc.isEncrypted())
                {
                    doc.setEncryptionDictionary(new PDEncryption());
                }
                @SuppressWarnings({"unchecked", "rawtypes"}) org.apache.pdfbox.pdmodel.encryption.SecurityHandler<org.apache.pdfbox.pdmodel.encryption.ProtectionPolicy> h = (org.apache.pdfbox.pdmodel.encryption.SecurityHandler) new NoMetadataHandler(policy);
                doc.getEncryption().setSecurityHandler(h);
            }
            else
            {
                doc.protect(policy);
            }
            doc.save(out);
        }
    }
}
