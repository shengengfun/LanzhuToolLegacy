// ------------------------------------------------------------------
// Copyright (C) 2015-2016 Maruko Toolbox Project
// 
//  Authors: LunarShaddow <aflyhorse@hotmail.com>
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
// express or implied.
// See the License for the specific language governing permissions
// and limitations under the License.
// -------------------------------------------------------------------
//

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Windows.Forms;

namespace mp4box
{
    public partial class FormUpdater : Form
    {
        private const string UpdateBinaryUrl = "https://maruko.appinn.me/config/lanzhutool.exe";

        /// <summary>
        /// Path of new (and temporary) assembly.
        /// </summary>
        private string newPath;

        /// <summary>
        /// Path of current assembly.
        /// </summary>
        private string exePath;

        /// <summary>
        /// Path of designated backup assembly.
        /// </summary>
        private string backupPath;

        /// <summary>
        /// Update Downloader.
        /// </summary>
        private System.Net.WebClient client;

        private readonly string logPath;

        /// <summary>
        /// Construnctor, initiate an update at targeted directory.
        /// </summary>
        /// <param name="startpath">The directory containing lanzhutool.exe.</param>
        /// <param name="date">The new release date.</param>
        public FormUpdater(string startpath, string date)
        {
            InitializeComponent();
            newPath = System.IO.Path.Combine(startpath, "lanzhutool.exe.new");
            exePath = System.IO.Path.Combine(startpath, "lanzhutool.exe");
            backupPath = System.IO.Path.Combine(startpath, "lanzhutool.exe.bak");
            string logDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "LanzhuTool", "logs");
            Directory.CreateDirectory(logDir);
            logPath = Path.Combine(logDir, "updater-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".log");
            labelDate.Text = date;
            labelStatus.Text = "准备下载更新包...";
            string[] iconPaths = new string[]
            {
                Path.Combine(Application.StartupPath, "icon.ico"),
                Path.Combine(Application.StartupPath, "Res", "lan.ico")
            };

            foreach (string iconPath in iconPaths)
            {
                if (!System.IO.File.Exists(iconPath))
                    continue;

                try { this.Icon = new Icon(iconPath); break; } catch { }
            }
        }

        #region UI Methods
        private void FormUpdater_Load(object sender, EventArgs e)
        {
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;
            client = new System.Net.WebClient();
            client.DownloadFileCompleted += client_DownloadFileCompleted;
            client.DownloadProgressChanged += client_DownloadProgressChanged;
            Log("开始下载更新包: " + UpdateBinaryUrl);
            client.DownloadFileAsync(new Uri(UpdateBinaryUrl), newPath);
        }

        private void buttonCancel_Click(object sender, EventArgs e)
        {
            if (client != null)
            {
                labelStatus.Text = "正在取消更新...";
                Log("用户取消更新。");
                client.CancelAsync();
            }
        }
        #endregion

        /// <summary>
        /// Update ProgressBar as requested.
        /// </summary>
        void client_DownloadProgressChanged(object sender, System.Net.DownloadProgressChangedEventArgs e)
        {
            progressBarDownload.Value = e.ProgressPercentage;
            labelStatus.Text = string.Format("下载中... {0}% ({1}/{2} KB)",
                e.ProgressPercentage,
                e.BytesReceived / 1024,
                e.TotalBytesToReceive > 0 ? e.TotalBytesToReceive / 1024 : 0);
        }

        private void Log(string message)
        {
            try
            {
                File.AppendAllText(logPath, string.Format("[{0}] {1}{2}", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"), message, Environment.NewLine), Encoding.UTF8);
            }
            catch
            {
            }
        }

        private bool ReplaceExecutableWithRollback()
        {
            if (!File.Exists(newPath))
            {
                Log("替换失败：未找到下载文件 " + newPath);
                return false;
            }

            if (!File.Exists(exePath))
            {
                Log("替换失败：未找到原始可执行文件 " + exePath);
                return false;
            }

            try
            {
                if (File.Exists(backupPath))
                    File.Delete(backupPath);

                File.Move(exePath, backupPath);
                File.Move(newPath, exePath);
                Log("替换成功，备份保留于: " + backupPath);
                return true;
            }
            catch (Exception ex)
            {
                Log("替换失败，尝试回滚: " + ex.Message);
                try
                {
                    if (File.Exists(exePath))
                        File.Delete(exePath);
                    if (File.Exists(backupPath))
                    {
                        File.Move(backupPath, exePath);
                        Log("回滚成功。");
                    }
                }
                catch (Exception rollbackEx)
                {
                    Log("回滚失败: " + rollbackEx.Message);
                }

                return false;
            }
        }

        /// <summary>
        /// Clean up. Remove incomplete file or do actually file replacing.
        /// </summary>
        void client_DownloadFileCompleted(object sender, AsyncCompletedEventArgs e)
        {
            buttonCancel.Enabled = false;

            if (e.Cancelled)
            {
                if (System.IO.File.Exists(newPath))
                    System.IO.File.Delete(newPath);
                labelStatus.Text = "已取消更新";
                Log("更新已取消，临时文件已清理。");
                this.Close();
            }
            else if (e.Error != null)
            {
                if (System.IO.File.Exists(newPath))
                    System.IO.File.Delete(newPath);

                labelStatus.Text = "下载失败";
                Log("下载失败: " + e.Error.Message);
                MessageBox.Show("下载更新失败：" + e.Error.Message + "\r\n详细日志：" + logPath, "升级失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
                this.Close();
            }
            else
            {
                labelStatus.Text = "下载完成，正在替换文件...";
                Log("下载完成，准备替换文件。");

                if (ReplaceExecutableWithRollback())
                {
                    labelStatus.Text = "升级完成，正在重启...";
                    Log("升级成功，应用即将重启。");
                    Application.Restart();
                }
                else
                {
                    labelStatus.Text = "升级失败，已尝试回滚";
                    MessageBox.Show("升级失败，已尝试回滚。\r\n详细日志：" + logPath, "升级失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    this.Close();
                }
            }
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            try
            {
                if (client != null)
                {
                    client.DownloadFileCompleted -= client_DownloadFileCompleted;
                    client.DownloadProgressChanged -= client_DownloadProgressChanged;
                    client.Dispose();
                    client = null;
                }
            }
            catch
            {
            }

            base.OnFormClosed(e);
        }
    }
}
