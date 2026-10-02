using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using LumiKeyMapper.Core;

namespace LumiKeyMapper.Services;

public sealed class SettingsStore
{
    public static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented=true, Converters={new JsonStringEnumConverter()} };
    public string DirectoryPath { get; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "LumiKeyMapper");
    public string FilePath => Path.Combine(DirectoryPath,"settings.json");
    public string? LoadWarning { get; private set; }
    public AppSettings Load()
    {
        if (!File.Exists(FilePath)) return new();
        try { return Read(FilePath); }
        catch (Exception ex)
        {
            var backup = FilePath + ".invalid-" + DateTime.Now.ToString("yyyyMMdd-HHmmss");
            var backedUp = false;
            try { File.Copy(FilePath,backup); backedUp = true; } catch { }
            LoadWarning = "配置无法读取，已停用映射并使用空白配置。" + (backedUp ? "原文件已备份。" : "原文件未改动，但无法另存备份。") + ex.Message;
            return new() { Enabled=false };
        }
    }
    public static AppSettings Read(string path)
    {
        var settings = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(path),JsonOptions) ?? throw new InvalidDataException("配置内容为空。");
        if (settings.Version != 1) throw new InvalidDataException("不支持此配置版本。");
        if (!settings.PauseKey.IsValid || settings.PauseKey.IsPulse) throw new InvalidDataException("暂停键无效。");
        if (settings.Rules == null || settings.Rules.Count > 2000) throw new InvalidDataException("映射规则列表无效或超过 2000 条。");
        if (settings.Rules.Any(r=>r == null || r.Name == null || r.ProcessName == null || r.TitleContains == null)) throw new InvalidDataException("规则字段不完整。");
        if (settings.Rules.Select(r=>r.Id).Distinct().Count() != settings.Rules.Count) throw new InvalidDataException("存在重复的规则编号。");
        foreach (var rule in settings.Rules)
        {
            var error = RuleValidator.Validate(rule,settings.Rules,settings.PauseKey);
            if (error != null) throw new InvalidDataException(error);
        }
        return settings;
    }
    public void Save(AppSettings settings)
    {
        Directory.CreateDirectory(DirectoryPath);
        var temporary = FilePath + ".tmp";
        File.WriteAllText(temporary,JsonSerializer.Serialize(settings,JsonOptions));
        File.Move(temporary,FilePath,true);
    }
}
