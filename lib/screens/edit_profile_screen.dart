import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_profile.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class EditProfileScreen extends StatefulWidget {
  final UserProfile profile;
  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  XFile? _picked;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 82, maxWidth: 900);
    if (image != null && mounted) setState(() => _picked = image);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الاسم مطلوب')));
      return;
    }
    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      String photoUrl = widget.profile.photoUrl;
      if (_picked != null) {
        final ref = FirebaseStorage.instance.ref('public/profiles/${user.uid}.jpg');
        await ref.putFile(File(_picked!.path), SettableMetadata(contentType: 'image/jpeg'));
        photoUrl = await ref.getDownloadURL();
      }
      await FirestoreService().updateUserProfile(uid: user.uid, name: name, photoUrl: photoUrl);
      await user.updateDisplayName(name);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث الملف الشخصي')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ الملف: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPhoto = widget.profile.photoUrl;
    return Scaffold(
      appBar: AppBar(title: const Text('تعديل الملف الشخصي')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 52,
                    backgroundImage: _picked != null
                        ? FileImage(File(_picked!.path))
                        : (currentPhoto.isNotEmpty ? NetworkImage(currentPhoto) : null) as ImageProvider?,
                    backgroundColor: AppColors.emeraldLight,
                    child: (_picked == null && currentPhoto.isEmpty)
                        ? Text(_name.text.isNotEmpty ? _name.text[0] : 'م', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800))
                        : null,
                  ),
                  const CircleAvatar(radius: 17, child: Icon(Icons.camera_alt, size: 18)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 26),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم')),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: widget.profile.email,
            enabled: false,
            decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
          ),
          const SizedBox(height: 22),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const CircularProgressIndicator(strokeWidth: 2) : const Text('حفظ التغييرات'),
          ),
        ],
      ),
    );
  }
}
