import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';

import '../../../services/auth_service.dart';
import '../../../services/cloudinary_service.dart';
import '../../../services/database_service.dart';
import '../../../services/language_service.dart';
import '../../../services/pdf_service.dart';
import '../../authentication/login_page.dart';
import '../../../theme/app_colors.dart';

// ─── Palette — website er rong (lib/theme/app_colors.dart) ───
const Color _emerald = BC.primary;
const Color _emeraldBright = BC.brand500; // home page er moto
const Color _emeraldSoft = BC.secondary;
const Color _lapis = BC.finance600;
const Color _terracotta = BC.destructive;
const Color _ivory = BC.background;
const Color _ink = BC.foreground;
const Color _muted = BC.mutedForeground;
const Color _line = BC.border;
const Color _danger = BC.destructive;

/// File save kore snackbar dekhay, "Open" button soho
Future<void> _saveAndNotify(
    BuildContext context, Uint8List bytes, String fileName) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final path = await PdfService.saveToDevice(bytes, fileName);
    final shown = path.contains('/Download/')
        ? 'Download/Biniyog Club'
        : LanguageService.tr('app files', 'অ্যাপ ফাইল');
    messenger.showSnackBar(
      SnackBar(
        content: Text(LanguageService.tr(
            'Saved to $shown', '$shown এ সেভ হয়েছে')),
        backgroundColor: _emerald,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: LanguageService.tr('Open', 'খুলুন'),
          textColor: BC.brand200,
          onPressed: () => PdfService.openFile(path),
        ),
      ),
    );
  } catch (e) {
    debugPrint('Save file error: $e');
    messenger.showSnackBar(
      SnackBar(
        content: Text(LanguageService.tr(
            'Could not save the file. Please check storage permission and try again.',
            'ফাইল সেভ করা যায়নি। স্টোরেজ পারমিশন চেক করে আবার চেষ্টা করুন।')),
        backgroundColor: _danger,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// In-app PDF viewer
// ═══════════════════════════════════════════════════════════
class PdfViewerScreen extends StatefulWidget {
  final String title;
  final Uint8List bytes;
  final String fileName;

  const PdfViewerScreen({
    super.key,
    required this.title,
    required this.bytes,
    required this.fileName,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  String? _localPath;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _savePdfToTemp();
  }

  Future<void> _savePdfToTemp() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${widget.fileName}');
      await tempFile.writeAsBytes(widget.bytes, flush: true);
      if (!mounted) return;
      setState(() => _localPath = tempFile.path);
    } catch (e) {
      debugPrint("Error saving temp PDF: $e");
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ivory,
      appBar: AppBar(
        backgroundColor: _ivory,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: _ink),
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: _ink, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        toolbarHeight: 54,
        actions: [
          IconButton(
            tooltip: LanguageService.tr('Download', 'ডাউনলোড'),
            icon: const Icon(Icons.download_rounded, color: _emerald),
            onPressed: () => _saveAndNotify(context, widget.bytes, widget.fileName),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _failed
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            LanguageService.tr('Could not open this PDF. Try downloading it instead.',
                'পিডিএফ খোলা যায়নি। ডাউনলোড করে দেখুন।'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: _muted),
          ),
        ),
      )
          : _localPath == null
          ? const Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: _emerald, strokeWidth: 2.4)))
          : PDFView(
        filePath: _localPath,
        enableSwipe: true,
        swipeHorizontal: true,
        autoSpacing: false,
        pageFling: true,
        pageSnap: true,
        defaultPage: 0,
        fitPolicy: FitPolicy.BOTH,
        preventLinkNavigation: false,
        onError: (e) {
          debugPrint('PDFView error: $e');
          if (mounted) setState(() => _failed = true);
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// In-app image viewer
// ═══════════════════════════════════════════════════════════
class ImageViewerScreen extends StatelessWidget {
  final String title;
  final Uint8List bytes;
  final String fileName;

  const ImageViewerScreen({
    super.key,
    required this.title,
    required this.bytes,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.white),
            onPressed: () => _saveAndNotify(context, bytes, fileName),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Documents Page
// ═══════════════════════════════════════════════════════════
class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  bool _isLoading = true;
  bool _needsLogin = false;
  bool _loadFailed = false;
  String _userId = '';

  Map<String, List<Map<String, dynamic>>> _categorizedDocs = {
    'contracts': [],
    'kycDocs': [],
    'paymentReceipts': [],
    'investmentReceipts': [],
    'groupInvestmentReceipts': [],
    'distributionStatements': [],
    'harvestReports': [],
    'projectDocs': [],
  };

  // Upload form
  final _uploadFormKey = GlobalKey<FormState>();
  String _selectedCategory = 'PAYMENT_RECEIPT';
  final _docNameController = TextEditingController();
  final _docDescController = TextEditingController();
  File? _selectedUploadFile;
  bool _isUploadingDoc = false;
  final ImagePicker _picker = ImagePicker();

  // Kon item er kaj cholche (loader dekhate)
  final Set<String> _busy = {};

  // Website er DocumentCategory enum er sathe mile — "Other" chilo, kintu DB
  // te sheta chupchap "Payment Receipt" hoye jeto, tai bad
  Map<String, String> get categoryDropdownOptions => {
    'PAYMENT_RECEIPT': LanguageService.tr('Payment Receipt', 'পেমেন্ট রিসিট'),
  };

  @override
  void initState() {
    super.initState();
    _loadDocumentsData();
  }

  @override
  void dispose() {
    _docNameController.dispose();
    _docDescController.dispose();
    super.dispose();
  }

  Future<void> _loadDocumentsData() async {
    if (mounted) setState(() => _isLoading = true);

    final userData = await AuthService.getUserData();
    final userId = userData?['id']?.toString() ?? '';

    if (userId.isEmpty) {
      if (mounted) {
        setState(() {
          _needsLogin = true;
          _isLoading = false;
        });
      }
      return;
    }

    final categorized = await DatabaseService.getDocumentsCategorized(userId);
    // Khali mane "kichu nei" naki "net nei" — alada kori
    final empty = categorized.values.every((l) => l.isEmpty);
    final failed = empty && DatabaseService.lastRequestFailed;

    if (!mounted) return;
    setState(() {
      _userId = userId;
      _categorizedDocs = categorized;
      _needsLogin = false;
      _loadFailed = failed;
      _isLoading = false;
    });
  }

  Future<void> _goToLogin() async {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
  }

  // ─── Helpers ──────────────────────────────────────────────
  String _trim(double v, int digits) {
    final s = v.toStringAsFixed(digits);
    return s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;
  }

  String _fmtBdt(double amount) {
    if (amount >= 10000000) return '৳${_trim(amount / 10000000, 2)} Cr';
    if (amount >= 100000) return '৳${_trim(amount / 100000, 2)}L';
    if (amount >= 1000) return '৳${_trim(amount / 1000, 1)}K';
    return '৳${amount.toStringAsFixed(0)}';
  }

  String _fmtSize(dynamic raw) {
    final b = (raw is num) ? raw.toInt() : int.tryParse('$raw') ?? 0;
    if (b <= 0) return '';
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / 1024).toStringAsFixed(0)} KB';
  }

  String _statusLabel(String st) {
    switch (st) {
      case 'NOT_STARTED':
        return LanguageService.tr('Not Started', 'শুরু হয়নি');
      case 'PENDING':
      case 'UNDER_REVIEW':
        return LanguageService.tr('Under Review', 'পর্যালোচনায়');
      case 'ACTIVE':
        return LanguageService.tr('Active', 'একটিভ');
      case 'CONFIRMED':
        return LanguageService.tr('Confirmed', 'নিশ্চিত');
      case 'PAYMENT_PENDING':
        return LanguageService.tr('Awaiting Payment', 'পেমেন্ট অপেক্ষমান');
      case 'COMPLETED':
      case 'MATURED':
        return LanguageService.tr('Completed', 'সম্পন্ন');
      case 'CANCELLED':
        return LanguageService.tr('Cancelled', 'বাতিল');
      case 'VERIFIED':
      case 'APPROVED':
        return LanguageService.tr('Verified', 'ভেরিফায়েড');
      case 'SUBMITTED':
        return LanguageService.tr('Under Review', 'পর্যালোচনায়');
      case 'REJECTED':
        return LanguageService.tr('Rejected', 'বাতিল');
      case 'RECEIPT_PENDING':
        return LanguageService.tr('Receipt pending', 'রসিদ বাকি');
      default:
      // Ojana status "Draft" bolbo na — ja ache tai dekhai
        if (st.isEmpty) return '—';
        final w = st.replaceAll('_', ' ').toLowerCase();
        return w[0].toUpperCase() + w.substring(1);
    }
  }

  Color _statusColor(String st) {
    switch (st) {
      case 'ACTIVE':
      case 'CONFIRMED':
      case 'VERIFIED':
      case 'APPROVED':
        return _emerald;
      case 'PAYMENT_PENDING':
      case 'SUBMITTED':
      case 'PENDING':
      case 'UNDER_REVIEW':
        return BC.chart4Deep;
      case 'NOT_STARTED':
      case 'RECEIPT_PENDING':
        return _muted;
      case 'COMPLETED':
      case 'MATURED':
        return _lapis;
      case 'CANCELLED':
      case 'REJECTED':
        return _danger;
      default:
        return _terracotta;
    }
  }

  bool _certificateReady(String status) =>
      status == 'CONFIRMED' ||
          status == 'ACTIVE' ||
          status == 'COMPLETED' ||
          status == 'MATURED';

  // ─── Certificate ──────────────────────────────────────────

  // Certificate er data website er certificate theke (database), QR e website
  // er link: https://biniyogclub.com/verify/<receiptNumber> — tai scan korle
  // website er PDF er motoi verify hoy.
  String _certFileName(Map<String, dynamic> doc) =>
      'Certificate_${doc['certificateNo'] ?? doc['id']}.pdf';

  Future<Uint8List?> _buildCert(Map<String, dynamic> doc) async {
    final key = 'cert-${doc['id']}';
    setState(() => _busy.add(key));
    try {
      final category = doc['category']?.toString() ?? '';
      if (category == 'GROUP_INVESTMENT_RECEIPT') {
        return await PdfService.buildGroupWebsiteCertificate(doc);
      }
      return await PdfService.buildWebsiteCertificate(doc);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF error: $e'),
            backgroundColor: _danger,
          ),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  bool _guardCertificate(Map<String, dynamic> doc) {
    final st = doc['status']?.toString() ?? '';
    if (_certificateReady(st)) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(LanguageService.tr(
            'Certificate will be available after your payment is approved.',
            'পেমেন্ট অনুমোদনের পর সার্টিফিকেট পাওয়া যাবে।')),
        backgroundColor: BC.chart4Deep,
      ),
    );
    return false;
  }

  Future<void> _viewCertificate(Map<String, dynamic> doc) async {
    if (!_guardCertificate(doc)) return;
    final bytes = await _buildCert(doc);
    if (bytes == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          title: LanguageService.tr(
              'Investment Certificate', 'ইনভেস্টমেন্ট সার্টিফিকেট'),
          bytes: bytes,
          fileName: _certFileName(doc),
        ),
      ),
    );
  }

  Future<void> _downloadCertificate(Map<String, dynamic> doc) async {
    if (!_guardCertificate(doc)) return;
    final bytes = await _buildCert(doc);
    if (bytes == null || !mounted) return;
    await _saveAndNotify(context, bytes, _certFileName(doc));
  }

  // ─── Uploaded documents ───────────────────────────────────
  Future<(Uint8List, String)?> _fetchDoc(Map<String, dynamic> item) async {
    final raw = item['fileUrl']?.toString() ?? '';
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LanguageService.tr(
              'File link not found.', 'ফাইলের লিঙ্ক পাওয়া যায়নি।')),
          backgroundColor: _danger,
        ),
      );
      return null;
    }
    final url = DatabaseService.formatImageUrl(raw);
    final key = 'doc-${item['id']}';
    setState(() => _busy.add(key));
    final bytes = await PdfService.downloadBytes(url);
    if (mounted) setState(() => _busy.remove(key));

    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LanguageService.tr(
                'Download failed. Check your internet.',
                'ডাউনলোড হয়নি। ইন্টারনেট চেক করুন।')),
            backgroundColor: _danger,
          ),
        );
      }
      return null;
    }
    final ext = PdfService.extensionFor(bytes, url);
    final name = item['name']?.toString() ?? 'Document';
    return (bytes, '${PdfService.safeFileName(name)}.$ext');
  }

  Future<void> _viewDoc(Map<String, dynamic> item) async {
    final res = await _fetchDoc(item);
    if (res == null || !mounted) return;
    final (bytes, fileName) = res;
    final title = item['name']?.toString() ?? 'Document';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfService.isPdf(bytes)
            ? PdfViewerScreen(title: title, bytes: bytes, fileName: fileName)
            : ImageViewerScreen(
            title: title, bytes: bytes, fileName: fileName),
      ),
    );
  }

  Future<void> _downloadDoc(Map<String, dynamic> item) async {
    final res = await _fetchDoc(item);
    if (res == null || !mounted) return;
    await _saveAndNotify(context, res.$1, res.$2);
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final name = item['name']?.toString() ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(LanguageService.tr('Delete document?', 'ডকুমেন্ট মুছবেন?'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
        content: Text(
          LanguageService.tr('"$name" will be removed from your documents.',
              '"$name" আপনার ডকুমেন্ট থেকে সরানো হবে।'),
          style: const TextStyle(fontSize: 13, color: _muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(LanguageService.tr('Cancel', 'বাতিল'), style: const TextStyle(color: _muted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _danger, foregroundColor: Colors.white),
            child: Text(LanguageService.tr('Delete', 'মুছুন')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final key = 'doc-${item['id']}';
    setState(() => _busy.add(key));
    final res = await DatabaseService.deleteUserDocument(
      userId: _userId,
      documentId: item['id'].toString(),
    );
    if (!mounted) return;
    setState(() => _busy.remove(key));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res['success'] == true
            ? LanguageService.tr('Document deleted.', 'ডকুমেন্ট মুছে ফেলা হয়েছে।')
            : (res['message']?.toString() ??
            LanguageService.tr('Could not delete.', 'মুছা যায়নি।'))),
        backgroundColor: res['success'] == true ? _emerald : _danger,
      ),
    );
    if (res['success'] == true) _loadDocumentsData();
  }

  // ─── Upload ───────────────────────────────────────────────
  Future<void> _pickUploadFile() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() => _selectedUploadFile = File(picked.path));
      }
    } catch (e) {
      debugPrint('Error picking document file: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LanguageService.tr('Could not open the image. Please try another one.',
              'ছবিটি খোলা যায়নি। অন্য একটি চেষ্টা করুন।')),
          backgroundColor: _danger,
        ),
      );
    }
  }

  Future<void> _handleUploadDocument() async {
    if (!_uploadFormKey.currentState!.validate()) return;

    if (_selectedUploadFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(LanguageService.tr(
              'Please select a file to upload.', 'একটি ফাইল নির্বাচন করুন।')),
          backgroundColor: _danger,
        ),
      );
      return;
    }

    setState(() => _isUploadingDoc = true);

    try {
      final bytes = await _selectedUploadFile!.readAsBytes();

      if (bytes.length > 10 * 1024 * 1024) {
        if (mounted) {
          setState(() => _isUploadingDoc = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LanguageService.tr(
                  'File is larger than 10 MB.', 'ফাইল ১০ MB এর বেশি।')),
              backgroundColor: _danger,
            ),
          );
        }
        return;
      }

      final cloudinaryUrl =
      await CloudinaryService.uploadImage(bytes, folder: 'user_documents');

      if (cloudinaryUrl == null || cloudinaryUrl.isEmpty) {
        if (mounted) {
          setState(() => _isUploadingDoc = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LanguageService.tr(
                  'Upload failed. Check your internet.',
                  'আপলোড হয়নি। ইন্টারনেট চেক করুন।')),
              backgroundColor: _danger,
            ),
          );
        }
        return;
      }

      final res = await DatabaseService.uploadUserDocument(
        userId: _userId,
        name: _docNameController.text.trim(),
        category: _selectedCategory,
        fileUrl: cloudinaryUrl,
        description: _docDescController.text.trim(),
        sizeBytes: bytes.length,
      );

      if (!mounted) return;
      setState(() => _isUploadingDoc = false);

      if (res['success'] == true) {
        _docNameController.clear();
        _docDescController.clear();
        setState(() => _selectedUploadFile = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LanguageService.tr('Document uploaded successfully!',
                'ডকুমেন্ট সফলভাবে আপলোড হয়েছে!')),
            backgroundColor: _emerald,
          ),
        );
        _loadDocumentsData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Upload failed.'),
            backgroundColor: _danger,
          ),
        );
      }
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) {
        setState(() => _isUploadingDoc = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LanguageService.tr('Upload failed. Please try again.',
                'আপলোড হয়নি। আবার চেষ্টা করুন।')),
            backgroundColor: _danger,
          ),
        );
      }
    }
  }

  // ═════════════════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    // "Agreements & Other Documents" section nei — oigulo gona hoy na
    final int totalCount = _categorizedDocs.entries
        .where((e) => e.key != 'projectDocs')
        .fold(0, (sum, e) => sum + e.value.length);

    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        return Scaffold(
          backgroundColor: _ivory,
          appBar: AppBar(
            backgroundColor: _ivory,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 54,
            iconTheme: const IconThemeData(color: _ink),
            title: Text(
              LanguageService.tr('Documents', 'ডকুমেন্টস'),
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w700,
                fontSize: 17.5,
              ),
            ),
          ),
          body: _isLoading
              ? const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(color: _emerald, strokeWidth: 2.4),
              ))
              : _needsLogin
              ? _buildMessage(
            Icons.lock_outline_rounded,
            LanguageService.tr('Please log in to see your documents',
                'ডকুমেন্ট দেখতে লগইন করুন'),
            null,
            LanguageService.tr('Log in', 'লগইন'),
            _goToLogin,
          )
              : _loadFailed
              ? _buildMessage(
            Icons.wifi_off_rounded,
            LanguageService.tr('Could not load your documents',
                'ডকুমেন্ট লোড করা যায়নি'),
            LanguageService.tr('Please check your internet connection.',
                'ইন্টারনেট সংযোগ চেক করুন।'),
            LanguageService.tr('Try again', 'আবার চেষ্টা করুন'),
            _loadDocumentsData,
          )
              : RefreshIndicator(
            onRefresh: _loadDocumentsData,
            color: _emerald,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 2, 16, 24 + MediaQuery.of(context).padding.bottom),
              children: [
                _buildSummary(totalCount),
                const SizedBox(height: 10),
                _buildSectionCard(
                  icon: Icons.workspace_premium_outlined,
                  color: _emerald,
                  soft: _emeraldSoft,
                  title: LanguageService.tr(
                      'Investment Certificates', 'ইনভেস্টমেন্ট সার্টিফিকেট'),
                  items: _categorizedDocs['investmentReceipts'] ?? [],
                  emptyMsg: LanguageService.tr(
                      'No certificates yet. A certificate appears here after admin approves your payment.',
                      'এখনো কোনো সার্টিফিকেট নেই। পেমেন্ট অনুমোদনের পর এখানে আসবে।'),
                  rowBuilder: _buildCertificateRow,
                  maxVisible: 2,
                  rowHeight: 104,
                ),
                const SizedBox(height: 10),
                // Website er deed (Investment Agreement) — admin approve korle website PDF banay
                _buildSectionCard(
                  icon: Icons.history_edu_rounded,
                  color: _emerald,
                  soft: _emeraldSoft,
                  title: LanguageService.tr('Investment Deeds', 'বিনিয়োগ দলিল'),
                  items: _categorizedDocs['contracts'] ?? [],
                  emptyMsg: LanguageService.tr(
                      'No deeds yet. Your deed appears here once your investment is approved and issued.',
                      'এখনো কোনো দলিল নেই। বিনিয়োগ অনুমোদনের পর দলিল তৈরি হলে এখানে আসবে।'),
                  rowBuilder: _buildFileRow,
                  maxVisible: 3,
                  rowHeight: 60,
                ),
                const SizedBox(height: 10),
                _buildSectionCard(
                  icon: Icons.apartment_rounded,
                  color: _emerald,
                  soft: _emeraldSoft,
                  title: LanguageService.tr(
                      'Group Investment Receipts', 'গ্রুপ ইনভেস্টমেন্ট রিসিট'),
                  items: _categorizedDocs['groupInvestmentReceipts'] ?? [],
                  emptyMsg: LanguageService.tr(
                      'No group investment receipts yet.',
                      'এখনো কোনো গ্রুপ ইনভেস্টমেন্ট রিসিট নেই।'),
                  rowBuilder: _buildCertificateRow,
                  maxVisible: 2,
                  rowHeight: 104,
                ),
                const SizedBox(height: 10),
                _buildSectionCard(
                  icon: Icons.receipt_long_outlined,
                  color: _emerald,
                  soft: _emeraldSoft,
                  title: LanguageService.tr(
                      'Payment Receipts', 'পেমেন্ট রিসিট'),
                  items: _categorizedDocs['paymentReceipts'] ?? [],
                  emptyMsg: LanguageService.tr('No payment receipts.',
                      'কোনো পেমেন্ট রিসিট নেই।'),
                  rowBuilder: _buildFileRow,
                  maxVisible: 4,
                  rowHeight: 60,
                ),
                const SizedBox(height: 10),
                _buildSectionCard(
                  icon: Icons.bar_chart_rounded,
                  color: _emerald,
                  soft: _emeraldSoft,
                  title: LanguageService.tr(
                      'Distribution Statements', 'লভ্যাংশ স্টেটমেন্ট'),
                  items: _categorizedDocs['distributionStatements'] ?? [],
                  emptyMsg: LanguageService.tr('No statements yet.',
                      'এখনো কোনো স্টেটমেন্ট নেই।'),
                  rowBuilder: _buildFileRow,
                  rowHeight: 60,
                ),
                const SizedBox(height: 10),
                _buildSectionCard(
                  icon: Icons.eco_outlined,
                  color: _emerald,
                  soft: _emeraldSoft,
                  title: LanguageService.tr(
                      'Harvest Reports', 'হারভেস্ট রিপোর্ট'),
                  items: _categorizedDocs['harvestReports'] ?? [],
                  emptyMsg: LanguageService.tr('No harvest reports.',
                      'কোনো হারভেস্ট রিপোর্ট নেই।'),
                  rowBuilder: _buildFileRow,
                  rowHeight: 60,
                ),
                const SizedBox(height: 12),
                _buildUploadDocumentFormCard(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Summary (upore) ─────────────────────────────────────
  Widget _buildSummary(int totalCount) {
    int n(String k) => _categorizedDocs[k]?.length ?? 0;
    final certs = n('investmentReceipts') + n('groupInvestmentReceipts');
    final ready = [...?_categorizedDocs['investmentReceipts'], ...?_categorizedDocs['groupInvestmentReceipts']]
        .where((d) => _certificateReady(d['status']?.toString() ?? ''))
        .length;

    Widget cell(String label, String value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(165))),
          ),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [_emeraldBright, _emerald],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                LanguageService.tr('MY DOCUMENTS', 'আমার নথিপত্র'),
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xC8FFFFFF), letterSpacing: 1.3),
              ),
              const Spacer(),
              Text(
                LanguageService.tr('$totalCount total', 'মোট $totalCount টি'),
                style: TextStyle(fontSize: 11.5, color: Colors.white.withAlpha(150)),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              cell(LanguageService.tr('Certificates', 'সার্টিফিকেট'), '$ready/$certs', Colors.white),
              cell(LanguageService.tr('Deeds', 'দলিল'), '${n('contracts')}', BC.brand200),
              cell(LanguageService.tr('Receipts', 'রিসিট'), '${n('paymentReceipts')}', BC.brand300),
              cell(LanguageService.tr('Statements', 'স্টেটমেন্ট'), '${n('distributionStatements')}', Colors.white),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, Color color, String tip, VoidCallback onTap) {
    return IconButton(
      tooltip: tip,
      onPressed: onTap,
      icon: Icon(icon, color: color, size: 20),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    );
  }

  // ─── Section card ─────────────────────────────────────────
  Widget _buildSectionCard({
    required IconData icon,
    required Color color,
    required Color soft,
    required String title,
    required List<Map<String, dynamic>> items,
    required String emptyMsg,
    required Widget Function(Map<String, dynamic>) rowBuilder,
    int maxVisible = 3,
    double rowHeight = 72,
  }) {
    // Beshi item hole card er bhitore scroll hobe (fixed uchchota)
    final scrollable = items.length > maxVisible;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: soft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 17),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: items.isEmpty ? _ivory : soft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${items.length}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: items.isEmpty ? _muted : color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(49, 0, 12, 12),
              child: Text(
                emptyMsg,
                style: const TextStyle(fontSize: 12.5, color: _muted, height: 1.4),
              ),
            )
          else ...[
            const Divider(height: 1, color: _line),
            if (scrollable) ...[
              _ScrollableSection(
                height: maxVisible * rowHeight + rowHeight * 0.45,
                itemCount: items.length,
                itemBuilder: (i) => rowBuilder(items[i]),
              ),
              const Divider(height: 1, color: _line),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.swipe_vertical_rounded, size: 14, color: _muted),
                    const SizedBox(width: 5),
                    Text(
                      LanguageService.tr('Scroll to see all ${items.length}',
                          'সব ${items.length} টি দেখতে স্ক্রল করুন'),
                      style: const TextStyle(fontSize: 11.5, color: _muted),
                    ),
                  ],
                ),
              ),
            ] else
              for (int i = 0; i < items.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: _line, indent: 12),
                rowBuilder(items[i]),
              ],
          ],
        ],
      ),
    );
  }

  Widget _statusPill(String status) {
    final c = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool filled = false,
    bool busy = false,
  }) {
    final child = busy
        ? SizedBox(
      width: 13,
      height: 13,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: filled ? Colors.white : _emerald,
      ),
    )
        : Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700)),
      ],
    );

    return filled
        ? FilledButton(
      onPressed: busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: _emerald,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 30),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
      child: child,
    )
        : OutlinedButton(
      onPressed: busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: _emerald,
        side: const BorderSide(color: _line),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 30),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
      child: child,
    );
  }

  // ─── Rows ─────────────────────────────────────────────────
  Widget _buildCertificateRow(Map<String, dynamic> item) {
    final status = item['status']?.toString() ?? '';
    final ready = _certificateReady(status);
    final busy = _busy.contains('cert-${item['id']}');
    final amt = (item['amountInvested'] as num?)?.toDouble() ?? 0.0;
    final certNo = item['certificateNo']?.toString() ?? '';
    final issued = PdfService.formatDate(item['issuedDate']?.toString());
    final title = (item['projectTitle']?.toString() ?? '').isNotEmpty
        ? item['projectTitle'].toString()
        : (item['name']?.toString() ?? '');
    final meta = [
      if (certNo.isNotEmpty) certNo,
      if (amt > 0) _fmtBdt(amt),
      if (issued.isNotEmpty) issued,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 38,
                decoration: BoxDecoration(
                  color: _emeraldSoft,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: _emerald.withAlpha(60)),
                ),
                child: const Icon(Icons.workspace_premium_rounded,
                    color: _emerald, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? '—' : title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        height: 1.3,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style: const TextStyle(fontSize: 11.5, color: _muted),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusPill(status),
            ],
          ),
          const SizedBox(height: 8),
          if (ready)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _actionButton(
                  icon: Icons.visibility_outlined,
                  label: LanguageService.tr('View', 'দেখুন'),
                  onTap: () => _viewCertificate(item),
                  busy: busy,
                ),
                const SizedBox(width: 8),
                _actionButton(
                  icon: Icons.download_rounded,
                  label: LanguageService.tr('Download PDF', 'পিডিএফ ডাউনলোড'),
                  onTap: () => _downloadCertificate(item),
                  filled: true,
                  busy: busy,
                ),
              ],
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _ivory,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_clock_outlined,
                      size: 15, color: _muted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      status == 'RECEIPT_PENDING'
                          ? LanguageService.tr('Available once the receipt number is issued',
                          'রসিদ নম্বর দেওয়া হলে পাওয়া যাবে')
                          : LanguageService.tr(
                          'Available after payment approval',
                          'পেমেন্ট অনুমোদনের পর পাওয়া যাবে'),
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }



  Widget _buildFileRow(Map<String, dynamic> item) {
    final busy = _busy.contains('doc-${item['id']}');
    final size = _fmtSize(item['sizeBytes']);
    final date = PdfService.formatDate(item['createdAt']?.toString());
    final url = item['fileUrl']?.toString().toLowerCase() ?? '';
    final isPdf = url.endsWith('.pdf') || url.startsWith('data:application/pdf');
    final desc = item['description']?.toString() ?? '';
    final mine = item['mine'] == true;

    return InkWell(
      onTap: busy ? null : () => _viewDoc(item),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isPdf ? BC.chart4Muted : _emeraldSoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                isPdf
                    ? Icons.picture_as_pdf_outlined
                    : Icons.image_outlined,
                color: isPdf ? BC.chart4Deep : _emerald,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (item['name']?.toString() ?? '').isEmpty ? '—' : item['name'].toString(),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        height: 1.3),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      desc,
                      style: const TextStyle(fontSize: 12, color: _ink, height: 1.3),
                    ),
                  ],
                  if ([date, size].any((x) => x.isNotEmpty)) ...[
                    const SizedBox(height: 1),
                    Text(
                      [if (date.isNotEmpty) date, if (size.isNotEmpty) size].join(' · '),
                      style: const TextStyle(fontSize: 11.5, color: _muted),
                    ),
                  ],
                ],
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _emerald),
                ),
              )
            else ...[
              _iconBtn(Icons.visibility_outlined, _muted, LanguageService.tr('View', 'দেখুন'), () => _viewDoc(item)),
              _iconBtn(Icons.download_rounded, _emerald, LanguageService.tr('Download', 'ডাউনলোড'),
                      () => _downloadDoc(item)),
              if (mine)
                _iconBtn(Icons.delete_outline_rounded, _danger, LanguageService.tr('Delete', 'মুছুন'),
                        () => _confirmDelete(item)),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Upload card ──────────────────────────────────────────
  InputDecoration _inputDeco(String label, String hint) => InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: _ivory,
    labelStyle: const TextStyle(color: _muted, fontSize: 13),
    hintStyle: const TextStyle(color: _muted, fontSize: 13),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _emerald, width: 1.4),
    ),
  );

  Widget _buildUploadDocumentFormCard() {
    final hasFile = _selectedUploadFile != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Form(
        key: _uploadFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _emeraldSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.cloud_upload_outlined,
                      color: _emerald, size: 17),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    LanguageService.tr('Upload a Document', 'ডকুমেন্ট আপলোড করুন'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: _ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              LanguageService.tr(
                'For investment payments, use "Submit Payment Proof" on the investment instead — that is what admin reviews.',
                'বিনিয়োগের পেমেন্টের জন্য বিনিয়োগের "পেমেন্ট প্রুফ জমা দিন" ব্যবহার করুন — অ্যাডমিন সেটাই যাচাই করে।',
              ),
              style: const TextStyle(fontSize: 12, color: _muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: _inputDeco(
                  LanguageService.tr('Category', 'ক্যাটাগরি'), ''),
              items: categoryDropdownOptions.entries.map((e) {
                return DropdownMenuItem<String>(
                  value: e.key,
                  child: Text(e.value, style: const TextStyle(fontSize: 13, color: _ink)),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedCategory = v);
              },
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickUploadFile,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                decoration: BoxDecoration(
                  color: hasFile ? _emeraldSoft : _ivory,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasFile ? _emerald : _line,
                    width: hasFile ? 1.4 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    if (hasFile)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          _selectedUploadFile!,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      const Icon(Icons.add_photo_alternate_outlined,
                          size: 26, color: _emerald),
                    const SizedBox(height: 6),
                    Text(
                      hasFile
                          ? LanguageService.tr(
                          'Tap to change file', 'ফাইল বদলাতে চাপ দিন')
                          : LanguageService.tr('Tap to select a file',
                          'ফাইল সিলেক্ট করতে চাপ দিন'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _emerald,
                      ),
                    ),
                    const SizedBox(height: 1),
                    const Text(
                      'JPEG, PNG · Max 10 MB',
                      style: TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _docNameController,
              decoration: _inputDeco(
                LanguageService.tr('Document name *', 'ডকুমেন্টের নাম *'),
                'e.g. Bank deposit slip',
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? LanguageService.tr('Required field', 'আবশ্যক')
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _docDescController,
              decoration: _inputDeco(
                LanguageService.tr(
                    'Description (optional)', 'বিবরণ (ঐচ্ছিক)'),
                'Brief description',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isUploadingDoc ? null : _handleUploadDocument,
              style: FilledButton.styleFrom(
                backgroundColor: _emerald,
                disabledBackgroundColor: _emerald.withAlpha(120),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isUploadingDoc
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
                  : Text(
                LanguageService.tr(
                    'Upload Document', 'ডকুমেন্ট আপলোড করুন'),
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(IconData icon, String title, String? subtitle,
      String buttonLabel, VoidCallback onTap) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: _emerald),
            const SizedBox(height: 10),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: _muted)),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: _emerald,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Card er bhitore scroll — page er scroll er sathe jhamela kore na:
// bhitorer list shesh hole baki touch page ke scroll kore
// ═══════════════════════════════════════════════════════════
class _ScrollableSection extends StatefulWidget {
  final double height;
  final int itemCount;
  final Widget Function(int) itemBuilder;

  const _ScrollableSection({
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  State<_ScrollableSection> createState() => _ScrollableSectionState();
}

class _ScrollableSectionState extends State<_ScrollableSection> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        radius: const Radius.circular(8),
        child: ListView.separated(
          controller: _controller,
          primary: false,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: widget.itemCount,
          separatorBuilder: (_, __) =>
          const Divider(height: 1, color: _line, indent: 12),
          itemBuilder: (_, i) => widget.itemBuilder(i),
        ),
      ),
    );
  }
}